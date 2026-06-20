import CryptoKit
import Foundation

@MainActor
final class OBSClient: ObservableObject {
    @Published private(set) var connectionState: OBSConnectionState = .disconnected
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var currentProgramSceneName: String?
    @Published private(set) var availableScenes: [OBSSceneSummary] = []

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveLoopTask: Task<Void, Never>?
    private var identifiedContinuation: CheckedContinuation<Void, Error>?
    private var pendingRequests: [String: CheckedContinuation<OBSRequestResponseData, Error>] = [:]
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var currentConfiguration: OBSConfiguration?

    func connect(using configuration: OBSConfiguration) async {
        guard configuration.isEnabled else {
            connectionState = .disconnected
            lastErrorMessage = "OBS integration is disabled."
            return
        }

        disconnect()
        currentConfiguration = configuration
        connectionState = .connecting
        lastErrorMessage = nil

        guard let url = URL(string: "ws://\(configuration.host):\(configuration.port)") else {
            connectionState = .error
            lastErrorMessage = "Invalid OBS WebSocket URL."
            return
        }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        receiveLoopTask = Task {
            await receiveLoop()
        }

        do {
            try await waitForIdentification()
            connectionState = .connected
            await refreshSceneList()
        } catch {
            connectionState = .error
            lastErrorMessage = error.localizedDescription
            disconnect()
        }
    }

    func disconnect() {
        receiveLoopTask?.cancel()
        receiveLoopTask = nil

        if let webSocketTask {
            webSocketTask.cancel(with: .goingAway, reason: nil)
        }

        webSocketTask = nil
        currentProgramSceneName = nil
        availableScenes = []
        connectionState = .disconnected
        resumeAllPendingRequests(with: OBSClientError.disconnected)
    }

    func reconnectIfNeeded() async {
        guard let currentConfiguration, currentConfiguration.isEnabled else { return }
        await connect(using: currentConfiguration)
    }

    func refreshSceneList() async {
        guard connectionState == .connected else { return }

        do {
            let response = try await sendRequest(type: "GetSceneList", data: Optional<EmptyOBSRequestData>.none)
            let scenes = response.responseData?["scenes"]?.arrayValue ?? []
            let summaries = scenes.compactMap { value -> OBSSceneSummary? in
                guard
                    let object = value.objectValue,
                    let name = object["sceneName"]?.stringValue
                else {
                    return nil
                }

                return OBSSceneSummary(name: name)
            }

            availableScenes = summaries
            currentProgramSceneName = response.responseData?["currentProgramSceneName"]?.stringValue
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func setCurrentProgramScene(sceneName: String) async {
        let trimmed = sceneName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard connectionState == .connected else { return }
        guard currentProgramSceneName != trimmed else { return }

        do {
            _ = try await sendRequest(
                type: "SetCurrentProgramScene",
                data: SetCurrentProgramSceneData(sceneName: trimmed)
            )
            currentProgramSceneName = trimmed
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func receiveLoop() async {
        guard let webSocketTask else { return }

        do {
            while !Task.isCancelled {
                let message = try await webSocketTask.receive()
                let data: Data

                switch message {
                case .string(let string):
                    data = Data(string.utf8)
                case .data(let payload):
                    data = payload
                @unknown default:
                    continue
                }

                try await handleMessage(data: data)
            }
        } catch {
            if Task.isCancelled { return }
            lastErrorMessage = error.localizedDescription
            connectionState = .error
            resumeAllPendingRequests(with: error)
        }
    }

    private func handleMessage(data: Data) async throws {
        let base = try decoder.decode(OBSBaseEnvelope.self, from: data)

        switch base.op {
        case .hello:
            let hello = try decoder.decode(OBSHelloEnvelope.self, from: data)
            try await sendIdentify(using: hello.d)
        case .identified:
            identifiedContinuation?.resume()
            identifiedContinuation = nil
        case .requestResponse:
            let response = try decoder.decode(OBSRequestResponseEnvelope.self, from: data)
            guard let continuation = pendingRequests.removeValue(forKey: response.d.requestId) else { return }

            if response.d.requestStatus.result {
                continuation.resume(returning: response.d)
            } else {
                continuation.resume(throwing: OBSClientError.requestFailed(response.d.requestStatus.comment ?? "OBS request failed."))
            }
        case .event:
            let event = try decoder.decode(OBSEventEnvelope.self, from: data)
            if event.d.eventType == "CurrentProgramSceneChanged" {
                currentProgramSceneName = event.d.eventData?["sceneName"]?.stringValue
            }
        default:
            break
        }
    }

    private func sendIdentify(using hello: OBSHelloData) async throws {
        let authentication = try authenticationValue(using: hello.authentication)
        let identify = OBSIdentifyEnvelope(
            d: OBSIdentifyData(
                rpcVersion: hello.rpcVersion,
                authentication: authentication,
                eventSubscriptions: 1 << 0
            )
        )

        let data = try encoder.encode(identify)
        guard let payload = String(data: data, encoding: .utf8) else {
            throw OBSClientError.encodingFailed
        }

        try await webSocketTask?.send(.string(payload))
    }

    private func authenticationValue(using auth: OBSAuthenticationData?) throws -> String? {
        guard let auth else { return nil }
        let password = currentConfiguration?.password ?? ""
        guard !password.isEmpty else { return nil }

        let secretInput = Data((password + auth.salt).utf8)
        let secret = Data(SHA256.hash(data: secretInput)).base64EncodedString()
        let authenticationInput = Data((secret + auth.challenge).utf8)
        return Data(SHA256.hash(data: authenticationInput)).base64EncodedString()
    }

    private func waitForIdentification() async throws {
        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)

            guard let self else { return }
            guard let continuation = self.identifiedContinuation else { return }

            self.identifiedContinuation = nil
            continuation.resume(throwing: OBSClientError.connectionTimedOut)
        }

        defer {
            timeoutTask.cancel()
        }

        try await withCheckedThrowingContinuation { continuation in
            identifiedContinuation = continuation
        }
    }

    private func sendRequest<RequestData: Encodable>(
        type: String,
        data: RequestData?
    ) async throws -> OBSRequestResponseData {
        guard connectionState == .connected || connectionState == .connecting else {
            throw OBSClientError.disconnected
        }

        let requestId = UUID().uuidString
        let envelope = OBSRequestEnvelope(
            d: OBSRequestData(
                requestType: type,
                requestId: requestId,
                requestData: data
            )
        )

        let encoded = try encoder.encode(envelope)
        guard let payload = String(data: encoded, encoding: .utf8) else {
            throw OBSClientError.encodingFailed
        }

        guard let webSocketTask else {
            throw OBSClientError.disconnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestId] = continuation

            let timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)

                guard let self else { return }
                guard let continuation = self.pendingRequests.removeValue(forKey: requestId) else { return }

                continuation.resume(throwing: OBSClientError.requestTimedOut)
            }

            Task { @MainActor [weak self] in
                do {
                    try await webSocketTask.send(.string(payload))
                } catch {
                    timeoutTask.cancel()

                    guard let self else { return }
                    self.pendingRequests.removeValue(forKey: requestId)?.resume(throwing: error)
                }
            }
        }
    }

    private func resumeAllPendingRequests(with error: Error) {
        pendingRequests.values.forEach { $0.resume(throwing: error) }
        pendingRequests.removeAll()
        identifiedContinuation?.resume(throwing: error)
        identifiedContinuation = nil
    }
}

private struct OBSBaseEnvelope: Decodable {
    let op: OBSOpCode
}

private struct EmptyOBSRequestData: Encodable {}

private struct SetCurrentProgramSceneData: Encodable {
    let sceneName: String
}

private enum OBSClientError: LocalizedError {
    case disconnected
    case encodingFailed
    case connectionTimedOut
    case requestTimedOut
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .disconnected:
            return "OBS is not connected."
        case .encodingFailed:
            return "Failed to encode an OBS WebSocket message."
        case .connectionTimedOut:
            return "OBS connection timed out during identification."
        case .requestTimedOut:
            return "OBS request timed out."
        case .requestFailed(let message):
            return message
        }
    }
}

private extension JSONValue {
    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}
