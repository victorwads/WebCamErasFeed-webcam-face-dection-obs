import AVFoundation
import Foundation

actor LocalCameraDeviceProvider {
    func authorizationStatus() -> LocalCameraAuthorizationStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .restricted
        }
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func listDevices() -> [LocalCameraDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )

        return discovery.devices.map {
            LocalCameraDevice(id: $0.uniqueID, localizedName: $0.localizedName)
        }
        .sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }
    }

    func deviceExists(uniqueID: String) -> Bool {
        listDevices().contains(where: { $0.id == uniqueID })
    }

    func localizedName(for uniqueID: String) -> String? {
        listDevices().first(where: { $0.id == uniqueID })?.localizedName
    }
}
