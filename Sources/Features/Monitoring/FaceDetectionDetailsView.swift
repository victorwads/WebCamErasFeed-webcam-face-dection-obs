import SwiftUI

struct FaceDetectionDetailsView: View {
    let result: FaceDetectionResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Face Detection")
                .font(.subheadline)
                .fontWeight(.medium)

            if let result {
                Text("Faces: \(result.faceCount)")
                Text("Largest face: \(result.largestFaceArea.formattedArea)")
                Text("Total face area: \(result.totalFaceArea.formattedArea)")

                if result.faces.isEmpty {
                    Text("No faces detected.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(result.faces.enumerated()), id: \.element.id) { index, face in
                        Text("Face \(index + 1): area \(face.normalizedArea.formattedArea), confidence \(face.confidence.formattedPercent)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No detection data available.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
    }
}
