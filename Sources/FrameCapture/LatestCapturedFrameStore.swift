import Foundation

actor LatestCapturedFrameStore {
    private var frame: CapturedFrame?

    func replace(with newFrame: CapturedFrame) {
        frame = newFrame
    }

    func current() -> CapturedFrame? {
        frame
    }

    func reset() {
        frame = nil
    }
}
