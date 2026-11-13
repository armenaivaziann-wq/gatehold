// Сборка трейлера: кадры PNG (Godot Movie Maker: --write-movie <папка>/frame.png) и звук WAV —
// в MP4 (H.264 + AAC) средствами macOS (AVFoundation), без сторонних программ.
// Запуск: swift tools/trailer/assemble.swift <папка с кадрами> <звук.wav> <выход.mp4> [fps]
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

let args = CommandLine.arguments
guard args.count >= 4 else {
    print("usage: assemble.swift <frames dir> <audio.wav> <out.mp4> [fps]")
    exit(1)
}
let framesDir = URL(fileURLWithPath: args[1])
let audioURL = URL(fileURLWithPath: args[2])
let outURL = URL(fileURLWithPath: args[3])
let fps = Int32(args.count > 4 ? Int(args[4]) ?? 30 : 30)

let files = try FileManager.default.contentsOfDirectory(atPath: framesDir.path)
    .filter { $0.hasSuffix(".png") }
    .sorted()
guard let first = files.first,
      let src0 = CGImageSourceCreateWithURL(framesDir.appendingPathComponent(first) as CFURL, nil),
      let img0 = CGImageSourceCreateImageAtIndex(src0, 0, nil) else {
    print("no frames")
    exit(1)
}
let width = img0.width
let height = img0.height

// 1) Видео без звука
let videoOnly = outURL.deletingLastPathComponent().appendingPathComponent("video_only.mp4")
try? FileManager.default.removeItem(at: videoOnly)
let writer = try AVAssetWriter(outputURL: videoOnly, fileType: .mp4)
let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 16_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoMaxKeyFrameIntervalKey: Int(fps),
    ],
]
let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let colorSpace = CGColorSpaceCreateDeviceRGB()
for (i, name) in files.enumerated() {
    autoreleasepool {
        guard let src = CGImageSourceCreateWithURL(framesDir.appendingPathComponent(name) as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let pool = adaptor.pixelBufferPool else { return }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        guard let buffer = pb else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                            space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        ctx?.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        while !input.isReadyForMoreMediaData { usleep(1000) }
        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
    }
    if i % 300 == 0 { print("frame \(i)/\(files.count)") }
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else {
    print("video failed: \(String(describing: writer.error))")
    exit(1)
}

// 2) Видео + звук → итоговый MP4
let comp = AVMutableComposition()
let videoAsset = AVURLAsset(url: videoOnly)
let audioAsset = AVURLAsset(url: audioURL)
let sem = DispatchSemaphore(value: 0)
Task {
    do {
        let vTrack = try await videoAsset.loadTracks(withMediaType: .video).first!
        let vDur = try await videoAsset.load(.duration)
        let cv = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try cv.insertTimeRange(CMTimeRange(start: .zero, duration: vDur), of: vTrack, at: .zero)
        if let aTrack = try await audioAsset.loadTracks(withMediaType: .audio).first {
            let aDur = try await audioAsset.load(.duration)
            let ca = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
            try ca.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(aDur, vDur)), of: aTrack, at: .zero)
        }
        try? FileManager.default.removeItem(at: outURL)
        let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough)!
        try await export.export(to: outURL, as: .mp4)
        print("wrote \(outURL.path) \(width)x\(height) \(files.count) frames")
    } catch {
        print("mux failed: \(error)")
    }
    sem.signal()
}
sem.wait()
try? FileManager.default.removeItem(at: videoOnly)
