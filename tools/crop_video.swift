// Crop and re-encode a video for the web (H.264 + AAC, fast start) using AVFoundation.
// Usage: swift tools/crop_video.swift in.mp4 out.mp4 x y width height [videoBitrate]
// e.g. strip pillarbox bars from a portrait clip in a 1280x720 frame: 438 0 404 720 2000000
import AVFoundation

let a = CommandLine.arguments
let src = URL(fileURLWithPath: a[1]), dst = URL(fileURLWithPath: a[2])
let crop = CGRect(x: Double(a[3])!, y: Double(a[4])!, width: Double(a[5])!, height: Double(a[6])!)
let bitrate = a.count > 7 ? Int(a[7])! : 2_000_000
try? FileManager.default.removeItem(at: dst)

let asset = AVURLAsset(url: src)
let vTrack = asset.tracks(withMediaType: .video)[0]
let aTrack = asset.tracks(withMediaType: .audio).first

let comp = AVMutableVideoComposition()
comp.renderSize = crop.size
comp.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(24, min(60, vTrack.nominalFrameRate.rounded()))))
let inst = AVMutableVideoCompositionInstruction()
inst.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: vTrack)
layer.setTransform(vTrack.preferredTransform.concatenating(CGAffineTransform(translationX: -crop.minX, y: -crop.minY)), at: .zero)
inst.layerInstructions = [layer]
comp.instructions = [inst]

let reader = try! AVAssetReader(asset: asset)
let vOut = AVAssetReaderVideoCompositionOutput(videoTracks: [vTrack], videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
vOut.videoComposition = comp
reader.add(vOut)
var aOut: AVAssetReaderTrackOutput?
if let t = aTrack {
    let o = AVAssetReaderTrackOutput(track: t, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
    reader.add(o); aOut = o
}

let writer = try! AVAssetWriter(outputURL: dst, fileType: .mp4)
writer.shouldOptimizeForNetworkUse = true
let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(crop.width), AVVideoHeightKey: Int(crop.height),
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]])
vIn.expectsMediaDataInRealTime = false
writer.add(vIn)
var aIn: AVAssetWriterInput?
if aOut != nil {
    let i = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 2, AVSampleRateKey: 44100, AVEncoderBitRateKey: 128_000])
    writer.add(i); aIn = i
}

reader.startReading(); writer.startWriting(); writer.startSession(atSourceTime: .zero)
let group = DispatchGroup()
func pump(_ input: AVAssetWriterInput, _ output: AVAssetReaderOutput, _ q: String) {
    group.enter()
    input.requestMediaDataWhenReady(on: DispatchQueue(label: q)) {
        while input.isReadyForMoreMediaData {
            if let s = output.copyNextSampleBuffer() { input.append(s) } else { input.markAsFinished(); group.leave(); return }
        }
    }
}
pump(vIn, vOut, "v")
if let i = aIn, let o = aOut { pump(i, o, "a") }
group.wait()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
if writer.status != .completed { print("FAILED", writer.error ?? reader.error ?? "unknown"); exit(1) }
print("wrote", dst.path)
