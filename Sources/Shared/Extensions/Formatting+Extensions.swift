import Foundation
import CoreGraphics

extension Double {
    var formattedSeconds: String {
        String(format: "%.1f s", self)
    }

    var formattedFPS: String {
        String(format: "%.2f FPS", self)
    }
}

extension CGFloat {
    var formattedArea: String {
        String(format: "%.3f", Double(self))
    }
}

extension Float {
    var formattedPercent: String {
        String(format: "%.0f%%", self * 100)
    }
}

extension TimeInterval {
    var formattedAge: String {
        if self < 1 {
            return String(format: "%.0f ms", self * 1000)
        }

        return String(format: "%.1f s", self)
    }
}
