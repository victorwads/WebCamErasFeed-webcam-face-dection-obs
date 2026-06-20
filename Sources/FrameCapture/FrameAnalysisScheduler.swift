import Foundation

struct FrameAnalysisScheduler {
    static func shouldAnalyze(
        cameraID: UUID,
        frameSequence: UInt64,
        lastAnalyzedFrameSequenceByCamera: [UUID: UInt64],
        inFlightCameraIDs: Set<UUID>
    ) -> Bool {
        guard !inFlightCameraIDs.contains(cameraID) else { return false }
        return lastAnalyzedFrameSequenceByCamera[cameraID] != frameSequence
    }
}
