//
//  VideoWriter.swift
//  LegoCam
//
//  Created by devin chalmers on 2/25/23.
//

import AVFoundation
import CoreImage
import CoreVideo
import QuartzCore

struct VideoWriter {
    enum VideoWritingError: Error {
        case emptyVideo
        case fileExists
        case pixelBufferCreationFailed
        case appendImageFailed
    }

    static func write(sequence images: [CGImage], to url: URL, framerate: Int = 30) async throws {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw VideoWritingError.fileExists
        }

        guard let firstImage = images.first else {
            throw VideoWritingError.emptyVideo
        }

        print("Starting to write to \(url)...")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: firstImage.width,
            AVVideoHeightKey: firstImage.height])
        input.expectsMediaDataInRealTime = false
        writer.add(input)

        let inputAdapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let context = CIContext()
        for (idx, image) in images.enumerated() {
            while !input.isReadyForMoreMediaData {
                continue
            }

            var pixelBuffer: CVPixelBuffer!
            if CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA, nil, &pixelBuffer) != 0 {
                throw VideoWritingError.pixelBufferCreationFailed
            }

            let ciImage = CIImage(cgImage: image)
            context.render(ciImage, to: pixelBuffer)

            if !inputAdapter.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(idx), timescale: CMTimeScale(framerate))) {
                throw VideoWritingError.appendImageFailed
            }
        }

        input.markAsFinished()

        await withCheckedContinuation({ (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                print("Finished writing!")
                continuation.resume()
            }
        })
    }
}
