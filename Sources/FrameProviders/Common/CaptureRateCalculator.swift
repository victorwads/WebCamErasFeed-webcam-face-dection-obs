import Foundation

enum CaptureRateCalculator {
    static func framesPerSecond(for captureInterval: TimeInterval) -> Double {
        let clampedInterval = min(max(captureInterval, 0.1), 10.0)
        return min(10.0, max(0.1, 1.0 / clampedInterval))
    }
}
