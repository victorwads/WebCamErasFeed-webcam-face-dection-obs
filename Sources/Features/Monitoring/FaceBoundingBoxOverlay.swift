import SwiftUI

struct FaceBoundingBoxOverlay: View {
    let imagePixelSize: CGSize
    let faces: [FaceObservationData]

    var body: some View {
        GeometryReader { geometry in
            let fitted = aspectFitRect(imageSize: imagePixelSize, containerSize: geometry.size)

            ZStack(alignment: .topLeading) {
                ForEach(Array(faces.enumerated()), id: \.element.id) { index, face in
                    let rect = convert(face.boundingBox, into: fitted)

                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .stroke(Color.green, lineWidth: 2)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)

                        Text("Face \(index + 1)\nArea: \(face.normalizedArea.formattedArea)\nConfidence: \(face.confidence.formattedPercent)")
                            .font(.caption2)
                            .padding(6)
                            .background(.black.opacity(0.7))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .position(
                                x: max(rect.minX + 70, 70),
                                y: max(rect.minY + 24, 24)
                            )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func convert(_ normalizedBoundingBox: CGRect, into targetRect: CGRect) -> CGRect {
        let width = normalizedBoundingBox.width * targetRect.width
        let height = normalizedBoundingBox.height * targetRect.height
        let x = targetRect.minX + normalizedBoundingBox.minX * targetRect.width
        let y = targetRect.minY + (1 - normalizedBoundingBox.maxY) * targetRect.height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func aspectFitRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let x = (containerSize.width - width) / 2
        let y = (containerSize.height - height) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
