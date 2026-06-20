import SwiftUI

struct DSFormField: View {
    let title: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
