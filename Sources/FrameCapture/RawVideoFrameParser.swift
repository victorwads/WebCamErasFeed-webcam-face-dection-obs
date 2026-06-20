import Foundation

struct RawVideoFrameParser {
    let frameSize: Int
    private(set) var bufferedData = Data()

    init(frameSize: Int) {
        self.frameSize = frameSize
    }

    mutating func append(_ chunk: Data) -> [Data] {
        guard !chunk.isEmpty else { return [] }

        bufferedData.append(chunk)
        trimIfNeeded()

        var frames: [Data] = []
        while bufferedData.count >= frameSize {
            let frame = bufferedData.prefix(frameSize)
            frames.append(Data(frame))
            bufferedData.removeFirst(frameSize)
        }

        return frames
    }

    mutating func reset() {
        bufferedData.removeAll(keepingCapacity: false)
    }

    private mutating func trimIfNeeded() {
        let maxBufferedBytes = frameSize * 4
        guard bufferedData.count > maxBufferedBytes else { return }
        bufferedData.removeFirst(bufferedData.count - maxBufferedBytes)
    }
}
