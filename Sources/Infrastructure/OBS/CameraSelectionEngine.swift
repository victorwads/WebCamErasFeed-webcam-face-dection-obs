import Foundation

struct CameraSelectionOutcome: Sendable {
    let selectedCameraID: UUID?
    let reason: String
    let didSwitch: Bool
    let lastSwitchAt: Date?
}

actor CameraSelectionEngine {
    private let stabilityDuration: TimeInterval
    private let switchCooldown: TimeInterval
    private var selectedCameraID: UUID?
    private var candidateCameraID: UUID?
    private var candidateSince: Date?
    private var lastSwitchAt: Date?

    init(stabilityDuration: TimeInterval = 0.8, switchCooldown: TimeInterval = 2.0) {
        self.stabilityDuration = stabilityDuration
        self.switchCooldown = switchCooldown
    }

    func reset() {
        selectedCameraID = nil
        candidateCameraID = nil
        candidateSince = nil
        lastSwitchAt = nil
    }

    func evaluate(
        scores: [UUID: CameraScore],
        cameraOrder: [UUID],
        now: Date = Date()
    ) -> CameraSelectionOutcome {
        let scoredWithFaces = scores.filter { $0.value.hasFaces }
        guard !scoredWithFaces.isEmpty else {
            return CameraSelectionOutcome(
                selectedCameraID: selectedCameraID,
                reason: "Keeping current camera: no faces",
                didSwitch: false,
                lastSwitchAt: lastSwitchAt
            )
        }

        let sorted = scoredWithFaces.sorted { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value > rhs.value
            }

            let lhsIndex = cameraOrder.firstIndex(of: lhs.key) ?? .max
            let rhsIndex = cameraOrder.firstIndex(of: rhs.key) ?? .max
            return lhsIndex < rhsIndex
        }

        guard let winner = sorted.first else {
            return CameraSelectionOutcome(
                selectedCameraID: selectedCameraID,
                reason: "Keeping current camera: no faces",
                didSwitch: false,
                lastSwitchAt: lastSwitchAt
            )
        }

        if let selectedCameraID, scores[selectedCameraID] == winner.value {
            return CameraSelectionOutcome(
                selectedCameraID: selectedCameraID,
                reason: "Keeping current camera: tie at \(winner.value.shortDescription)",
                didSwitch: false,
                lastSwitchAt: lastSwitchAt
            )
        }

        if winner.key == selectedCameraID {
            candidateCameraID = nil
            candidateSince = nil
            return CameraSelectionOutcome(
                selectedCameraID: winner.key,
                reason: winner.value.shortDescription,
                didSwitch: false,
                lastSwitchAt: lastSwitchAt
            )
        }

        if let lastSwitchAt, now.timeIntervalSince(lastSwitchAt) < switchCooldown {
            return CameraSelectionOutcome(
                selectedCameraID: selectedCameraID,
                reason: "Cooldown active, best candidate: \(winner.value.shortDescription)",
                didSwitch: false,
                lastSwitchAt: self.lastSwitchAt
            )
        }

        if candidateCameraID != winner.key {
            candidateCameraID = winner.key
            candidateSince = now
            return CameraSelectionOutcome(
                selectedCameraID: selectedCameraID,
                reason: "Waiting stability: \(winner.value.shortDescription)",
                didSwitch: false,
                lastSwitchAt: lastSwitchAt
            )
        }

        if let candidateSince, now.timeIntervalSince(candidateSince) < stabilityDuration {
            return CameraSelectionOutcome(
                selectedCameraID: selectedCameraID,
                reason: "Holding candidate: \(winner.value.shortDescription)",
                didSwitch: false,
                lastSwitchAt: lastSwitchAt
            )
        }

        selectedCameraID = winner.key
        candidateCameraID = nil
        candidateSince = nil
        lastSwitchAt = now

        return CameraSelectionOutcome(
            selectedCameraID: winner.key,
            reason: winner.value.shortDescription,
            didSwitch: true,
            lastSwitchAt: now
        )
    }
}
