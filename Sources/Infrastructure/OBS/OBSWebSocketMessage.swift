import Foundation

enum OBSOpCode: Int, Codable {
    case hello = 0
    case identify = 1
    case identified = 2
    case event = 5
    case request = 6
    case requestResponse = 7
}

struct OBSHelloEnvelope: Decodable {
    let op: OBSOpCode
    let d: OBSHelloData
}

struct OBSHelloData: Decodable {
    let rpcVersion: Int
    let authentication: OBSAuthenticationData?
}

struct OBSAuthenticationData: Decodable {
    let challenge: String
    let salt: String
}

struct OBSIdentifyEnvelope: Encodable {
    let op: OBSOpCode = .identify
    let d: OBSIdentifyData
}

struct OBSIdentifyData: Encodable {
    let rpcVersion: Int
    let authentication: String?
    let eventSubscriptions: Int?
}

struct OBSRequestEnvelope<RequestData: Encodable>: Encodable {
    let op: OBSOpCode = .request
    let d: OBSRequestData<RequestData>
}

struct OBSRequestData<RequestData: Encodable>: Encodable {
    let requestType: String
    let requestId: String
    let requestData: RequestData?
}

struct OBSRequestResponseEnvelope: Decodable {
    let op: OBSOpCode
    let d: OBSRequestResponseData
}

struct OBSRequestResponseData: Decodable {
    let requestType: String?
    let requestId: String
    let requestStatus: OBSRequestStatus
    let responseData: [String: JSONValue]?
}

struct OBSRequestStatus: Decodable {
    let result: Bool
    let code: Int
    let comment: String?
}

struct OBSIdentifiedEnvelope: Decodable {
    let op: OBSOpCode
}

struct OBSEventEnvelope: Decodable {
    let op: OBSOpCode
    let d: OBSEventData
}

struct OBSEventData: Decodable {
    let eventType: String
    let eventIntent: Int?
    let eventData: [String: JSONValue]?
}

enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        switch self {
        case .int(let value):
            return value
        case .double(let value):
            return Int(value)
        default:
            return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .int(let value):
            return Double(value)
        case .double(let value):
            return value
        default:
            return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
}

struct OBSSceneSummary: Identifiable, Equatable {
    let id = UUID()
    let name: String
}
