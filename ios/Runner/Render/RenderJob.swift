import AVFoundation
import CoreImage
import Foundation

/// Where a render stands, reported on the main queue.
struct RenderCallbacks {
    let progress: (Double) -> Void
    let finished: (Result<Void, Error>) -> Void
}

/// What a render needs once the video has been opened.
private struct PreparedRender {
    let composition: AVMutableComposition
    let reader: AVAssetReader
    let videoOutput: AVAssetReaderTrackOutput
    let audioOutput: AVAssetReaderTrackOutput?
    let writer: AVAssetWriter
    let videoInput: AVAssetWriterInput
    let audioInput: AVAssetWriterInput?
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let composer: FrameComposer
    let orientation: CGAffineTransform
}

/// One export (spec FR-9): the clip is cut out of the video into a composition, so every frame
/// carries its own time counted from the clip start, which the crop and the caption lines both
/// read (spec §6.3.2). Each frame is drawn by `FrameComposer`, then `AVAssetWriter` encodes
/// hardware H.264 and AAC. Frames and audio are read and written on their own queues.
final class RenderJob {
    private static let progressInterval: TimeInterval = 0.25

    private let spec: RenderSpec
    private let callbacks: RenderCallbacks
    private let videoQueue = DispatchQueue(label: "status_studio.render.video")
    private let audioQueue = DispatchQueue(label: "status_studio.render.audio")
    private let lock = NSLock()
    private var isFinished = false
    private var unfinishedStreams = 0
    private var lastProgressAt = Date.distantPast
    private var prepared: PreparedRender?

    init(spec: RenderSpec, callbacks: RenderCallbacks) {
        self.spec = spec
        self.callbacks = callbacks
    }

    func start() {
        Task {
            do {
                let ready = try await prepare()
                guard !hasStopped else { return }
                try begin(ready)
            } catch {
                finish(.failure(error))
            }
        }
    }

    /// Stops the render and deletes the partial file (FR-9). Nothing is reported afterwards.
    func cancel() {
        stop(reporting: nil)
    }

    // MARK: Finishing

    /// The first call wins. A failure or a cancel stops the reader and the writer and deletes the
    /// partial file; `result` nil is a cancel, which reports nothing.
    private func stop(reporting result: Result<Void, Error>?) {
        lock.lock()
        let alreadyFinished = isFinished
        isFinished = true
        lock.unlock()
        guard !alreadyFinished else { return }
        if case .success = result {
            DispatchQueue.main.async { self.callbacks.finished(.success(())) }
            return
        }
        prepared?.reader.cancelReading()
        prepared?.writer.cancelWriting()
        try? FileManager.default.removeItem(atPath: spec.outputPath)
        guard let result else { return }
        DispatchQueue.main.async { self.callbacks.finished(result) }
    }

    private func finish(_ result: Result<Void, Error>) {
        stop(reporting: result)
    }

    private var hasStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isFinished
    }

    // MARK: Opening the video

    private func prepare() async throws -> PreparedRender {
        let asset = AVURLAsset(url: URL(fileURLWithPath: spec.inputPath))
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw RenderSpecError(message: "The video has no picture.")
        }
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let orientation = try await videoTrack.load(.preferredTransform)
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let assetDuration = try await asset.load(.duration)
        let composition = AVMutableComposition()
        let clip = try clipRange(within: assetDuration)
        let videoCopy = try copy(videoTrack, of: clip, into: composition)
        let audioCopy = try audioTrack.map { try copy($0, of: clip, into: composition) }
        var audioFormat: AudioFormat?
        if let audioTrack { audioFormat = try await audioFormatOf(audioTrack) }
        let outputs = try readerOutputs(video: videoCopy, audio: audioCopy, audioFormat: audioFormat, composition: composition)
        let writing = try writerInputs(frameRate: frameRate, audioFormat: audioFormat)
        let ready = PreparedRender(
            composition: composition,
            reader: outputs.reader,
            videoOutput: outputs.video,
            audioOutput: outputs.audio,
            writer: writing.writer,
            videoInput: writing.video,
            audioInput: writing.audio,
            adaptor: writing.adaptor,
            composer: try FrameComposer(spec: spec),
            orientation: orientation
        )
        prepared = ready
        return ready
    }

    private func clipRange(within assetDuration: CMTime) throws -> CMTimeRange {
        let start = CMTime(value: spec.clipStartMs, timescale: 1000)
        let end = min(CMTime(value: spec.clipEndMs, timescale: 1000), assetDuration)
        guard end > start else { throw RenderSpecError(message: "The clip is empty.") }
        return CMTimeRange(start: start, end: end)
    }

    private func copy(_ track: AVAssetTrack, of clip: CMTimeRange, into composition: AVMutableComposition) throws -> AVMutableCompositionTrack {
        guard let copy = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw RenderSpecError(message: "Couldn't open the video for editing.")
        }
        try copy.insertTimeRange(clip, of: track, at: .zero)
        return copy
    }

    private func audioFormatOf(_ track: AVAssetTrack) async throws -> AudioFormat {
        let descriptions = try await track.load(.formatDescriptions)
        let description = descriptions.first
        let basic = description.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        return AudioFormat(
            sampleRate: basic?.mSampleRate ?? 44100,
            channels: min(2, max(1, Int(basic?.mChannelsPerFrame ?? 2)))
        )
    }

    private func readerOutputs(
        video: AVMutableCompositionTrack,
        audio: AVMutableCompositionTrack?,
        audioFormat: AudioFormat?,
        composition: AVMutableComposition
    ) throws -> (reader: AVAssetReader, video: AVAssetReaderTrackOutput, audio: AVAssetReaderTrackOutput?) {
        let reader = try AVAssetReader(asset: composition)
        let videoOutput = AVAssetReaderTrackOutput(track: video, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        videoOutput.alwaysCopiesSampleData = false
        reader.add(videoOutput)
        var audioOutput: AVAssetReaderTrackOutput?
        if let audio, let audioFormat {
            let output = AVAssetReaderTrackOutput(track: audio, outputSettings: audioFormat.decodedSettings)
            reader.add(output)
            audioOutput = output
        }
        return (reader, videoOutput, audioOutput)
    }

    private func writerInputs(frameRate: Float, audioFormat: AudioFormat?) throws -> (
        writer: AVAssetWriter, video: AVAssetWriterInput, audio: AVAssetWriterInput?,
        adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) {
        try? FileManager.default.removeItem(atPath: spec.outputPath)
        let writer = try AVAssetWriter(outputURL: URL(fileURLWithPath: spec.outputPath), fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: try videoSettings(frameRate: frameRate))
        video.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: spec.outputWidth,
            kCVPixelBufferHeightKey as String: spec.outputHeight,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        guard writer.canAdd(video) else { throw RenderSpecError(message: "Couldn't set up the video encoder.") }
        writer.add(video)
        var audio: AVAssetWriterInput?
        if let audioFormat {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: try audioSettings(for: audioFormat))
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw RenderSpecError(message: "Couldn't set up the audio encoder.") }
            writer.add(input)
            audio = input
        }
        return (writer, video, audio, adaptor)
    }

    private func videoSettings(frameRate: Float) throws -> [String: Any] {
        guard spec.videoMimeType == "video/avc" else {
            throw RenderSpecError(message: "Can't encode \(spec.videoMimeType).")
        }
        let framesPerSecond = Double(frameRate > 0 ? min(frameRate, 30) : 30)
        let bitsPerPixel = 0.12
        return [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: spec.outputWidth,
            AVVideoHeightKey: spec.outputHeight,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(Double(spec.outputWidth * spec.outputHeight) * framesPerSecond * bitsPerPixel),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: framesPerSecond,
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
            ],
        ]
    }

    private func audioSettings(for format: AudioFormat) throws -> [String: Any] {
        guard spec.audioMimeType == "audio/mp4a-latm" else {
            throw RenderSpecError(message: "Can't encode \(spec.audioMimeType).")
        }
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channels,
            AVEncoderBitRateKey: 64_000 * format.channels,
        ]
    }

    // MARK: Copying frames and audio

    private func begin(_ ready: PreparedRender) throws {
        guard ready.reader.startReading() else { throw ready.reader.error ?? RenderSpecError(message: "Couldn't read the video.") }
        guard ready.writer.startWriting() else { throw ready.writer.error ?? RenderSpecError(message: "Couldn't write the video.") }
        ready.writer.startSession(atSourceTime: .zero)
        lock.lock()
        unfinishedStreams = ready.audioInput == nil ? 1 : 2
        lock.unlock()
        copyFrames(ready)
        copyAudio(ready)
    }

    private func copyFrames(_ ready: PreparedRender) {
        let seconds = CMTimeGetSeconds(ready.composition.duration)
        ready.videoInput.requestMediaDataWhenReady(on: videoQueue) { [weak self] in
            guard let self else { return }
            while ready.videoInput.isReadyForMoreMediaData, !self.hasStopped {
                guard let sample = ready.videoOutput.copyNextSampleBuffer() else {
                    ready.videoInput.markAsFinished()
                    self.streamEnded()
                    return
                }
                do {
                    try self.write(sample, from: ready)
                    self.reportProgress(Double(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))) / seconds)
                } catch {
                    self.finish(.failure(error))
                    return
                }
            }
        }
    }

    private func write(_ sample: CMSampleBuffer, from ready: PreparedRender) throws {
        guard let pixels = CMSampleBufferGetImageBuffer(sample) else { return }
        guard let pool = ready.adaptor.pixelBufferPool else {
            throw RenderSpecError(message: "The video encoder has no buffers.")
        }
        var output: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output)
        guard let output else { throw RenderSpecError(message: "Out of memory for a frame.") }
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        try ready.composer.render(
            SourceFrame(pixels: pixels, orientation: ready.orientation, timeMs: clipTimeMs(time)),
            into: output
        )
        guard ready.adaptor.append(output, withPresentationTime: time) else {
            throw ready.writer.error ?? RenderSpecError(message: "Couldn't write a frame.")
        }
    }

    private func copyAudio(_ ready: PreparedRender) {
        guard let input = ready.audioInput, let output = ready.audioOutput else { return }
        input.requestMediaDataWhenReady(on: audioQueue) { [weak self] in
            guard let self else { return }
            while input.isReadyForMoreMediaData, !self.hasStopped {
                guard let sample = output.copyNextSampleBuffer() else {
                    input.markAsFinished()
                    self.streamEnded()
                    return
                }
                guard input.append(sample) else {
                    self.finish(.failure(ready.writer.error ?? RenderSpecError(message: "Couldn't write the sound.")))
                    return
                }
            }
        }
    }

    /// The writer is closed once the picture and the sound are both through.
    private func streamEnded() {
        lock.lock()
        unfinishedStreams -= 1
        let allDone = unfinishedStreams == 0
        lock.unlock()
        guard allDone, !hasStopped, let writer = prepared?.writer else { return }
        writer.finishWriting { [weak self] in
            guard let self else { return }
            if writer.status == .completed {
                self.stop(reporting: .success(()))
            } else {
                self.finish(.failure(writer.error ?? RenderSpecError(message: "Export failed.")))
            }
        }
    }

    private func reportProgress(_ fraction: Double) {
        let now = Date()
        guard now.timeIntervalSince(lastProgressAt) >= RenderJob.progressInterval else { return }
        lastProgressAt = now
        let shown = min(1, max(0, fraction))
        DispatchQueue.main.async { self.callbacks.progress(shown) }
    }
}

private struct AudioFormat {
    let sampleRate: Double
    let channels: Int

    /// What the reader decodes to, at the rate and channel count the encoder gets.
    var decodedSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }
}
