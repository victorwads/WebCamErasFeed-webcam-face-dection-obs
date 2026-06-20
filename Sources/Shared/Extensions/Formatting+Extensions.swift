import Foundation

extension Double {
    var formattedSeconds: String {
        String(format: "%.1f s", self)
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
