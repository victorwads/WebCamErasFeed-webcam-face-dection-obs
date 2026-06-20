import SwiftUI

struct CaptureIntervalSection: View {
    @Binding var preferences: AppPreferences

    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Capture Interval")
                    .font(.headline)

                HStack {
                    Slider(
                        value: $preferences.captureInterval,
                        in: 0.1...10.0,
                        step: 0.1
                    )
                    .onChange(of: preferences.captureInterval) {
                        preferences.captureInterval = preferences.clampedCaptureInterval
                    }

                    Text(preferences.captureInterval.formattedSeconds)
                        .monospacedDigit()
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
    }
}
