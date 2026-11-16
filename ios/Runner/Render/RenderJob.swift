import AVFoundation
import CoreImage
import Foundation

/// Where a render stands, reported on the main queue.
struct RenderCallbacks {
    let progress: (Double) -> Void
    let finished: (Result<Void, Error>) -> Void
}

/// The clip's tracks, copied into the composition, and the sound's format.
private struct ClipTracks {
    let video: AVMutableCompositionTrack
    let audio: AVMutableCompositionTrack?
    let audioFormat: AudioFormat?
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
///
/// The first of `cancel`, a failure and the end of the writing decides how the job ends. Every
/// call into the reader and the writer that could meet a cancelled one runs inside
/// `whileRunning`, which holds the lock the ending needs; AVFoundation raises an Objective-C
/// exception, which Swift can't catch, when a cancelled writer is asked to carry on.
final class RenderJob {
    private static let progressInterval: TimeInterval = 0.25

    private let spec: RenderSpec
    private let callbacks: RenderCallbacks
    private let gate: ForegroundGate
    private let videoQueue = DispatchQueue(label: "status_studio.render.video")
    private let audioQueue = DispatchQueue(label: "status_studio.render.audio")
    private let lock = NSLock()
    private var hasEnded = false
    private var unfinishedStreams = 0
    private var lastProgressAt = Date.distantPast
    private var prepared: PreparedRender?

    init(spec: RenderSpec, callbacks: RenderCallbacks, gate: ForegroundGate) {
        self.spec = spec
        self.callbacks = callbacks
        self.gate = gate
    }

    func start() {
        Task {
            do {
                let ready = try await prepare()
                try begin(ready)
            } catch {
                fail(error)
            }
        }
    }

    /// Stops the render and deletes the partial file (FR-9). Nothing is reported afterwards.
    func cancel() {
        guard claimEnd() else { return }
        abandonWork()
    }

    // MARK: How it ends

    /// True for the first caller only.
    private func claimEnd() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !hasEnded else { return false }
        hasEnded = true
        return true
    }

    private var hasStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasEnded
    }

    /// Runs `body` only while the job has not ended, and keeps the ending from starting until it
    /// is through.
    private func whileRunning<Result>(_ body: () throws -> Result) rethrows -> Result? {
        lock.lock()
        defer { lock.unlock() }
        guard !hasEnded else { return nil }
        return try body()
    }

    private func fail(_ error: Error) {
        guard claimEnd() else { return }
        abandonWork()
        DispatchQueue.main.async { self.callbacks.finished(.failure(error)) }
    }

    private func succeed() {
        guard claimEnd() else { return }
        release()
        DispatchQueue.main.async { self.callbacks.finished(.success(())) }
    }

    /// Stops the reader and the writer and deletes the partial file.
    private func abandonWork() {
        let work = release()
        work?.reader.cancelReading()
        work?.writer.cancelWriting()
        try? FileManager.default.removeItem(atPath: spec.outputPath)
    }

    /// Lets go of everything the render held, so a finished export holds no memory: the
    /// writer's inputs keep their blocks, which would otherwise keep the writer.
    @discardableResult
    private func release() -> PreparedRender? {
        lock.lock()
        defer { lock.unlock() }
        let released = prepared
        prepared = nil
        return released
    }

    private func currentWork() -> PreparedRender? {
        lock.lock()
        defer { lock.unlock() }
        return prepared
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
        var audioFormat: AudioFormat?
        if let audioTrack { audioFormat = try await audioFormatOf(audioTrack) }
        let tracks = ClipTracks(
            video: try copy(videoTrack, of: clip, into: composition),
            audio: try audioTrack.map { try copy($0, of: clip, into: composition) },
            audioFormat: audioFormat
        )
        let outputs = try readerOutputs(for: tracks, in: composition)
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
        let stored = whileRunning { prepared = ready }
        guard stored != nil else { throw CancellationError() }
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
        let basic = descriptions.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        return AudioFormat(
            sampleRate: basic?.mSampleRate ?? 44100,
            channels: Int(basic?.mChannelsPerFrame ?? 2)
        )
    }

    private func readerOutputs(
        for tracks: ClipTracks,
        in composition: AVMutableComposition
    ) throws -> (reader: AVAssetReader, video: AVAssetReaderTrackOutput, audio: AVAssetReaderTrackOutput?) {
        let reader = try AVAssetReader(asset: composition)
        let videoOutput = AVAssetReaderTrackOutput(track: tracks.video, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        videoOutput.alwaysCopiesSampleData = false
        reader.add(videoOutput)
        var audioOutput: AVAssetReaderTrackOutput?
        if let audio = tracks.audio, let format = tracks.audioFormat {
            let output = AVAssetReaderTrackOutput(track: audio, outputSettings: format.decodedSettings)
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
        // The same rate as Android's reel (spec FR-48), whatever the output size.
        let reelVideoBitRate = 4_000_000
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
                AVVideoAverageBitRateKey: reelVideoBitRate,
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
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channels,
        ]
        // The encoder refuses a high rate of bits on a low rate of samples, so it picks its own.
        if format.sampleRate >= AudioFormat.rateForChosenBitRate {
            settings[AVEncoderBitRateKey] = 64_000 * format.channels
        }
        return settings
    }

    // MARK: Copying frames and audio

    private func begin(_ ready: PreparedRender) throws {
        let started: Void? = try whileRunning {
            guard ready.reader.startReading() else { throw ready.reader.error ?? RenderSpecError(message: "Couldn't read the video.") }
            guard ready.writer.startWriting() else { throw ready.writer.error ?? RenderSpecError(message: "Couldn't write the video.") }
            ready.writer.startSession(atSourceTime: .zero)
            unfinishedStreams = ready.audioInput == nil ? 1 : 2
        }
        guard started != nil else { return }
        copyFrames(ready)
        copyAudio(ready)
    }

    // The blocks keep only `self`, weakly: the writer's inputs keep the blocks, so a block that
    // held the writer would keep it alive for good.
    private func copyFrames(_ ready: PreparedRender) {
        let seconds = CMTimeGetSeconds(ready.composition.duration)
        ready.videoInput.requestMediaDataWhenReady(on: videoQueue) { [weak self] in
            guard let self else { return }
            while let work = self.currentWork(), work.videoInput.isReadyForMoreMediaData {
                var reachedEnd = false
                autoreleasepool { reachedEnd = !self.copyNextFrame(of: work, seconds: seconds) }
                if self.hasStopped { return }
                if reachedEnd {
                    self.endOfStream(reader: work.reader, input: work.videoInput)
                    return
                }
            }
        }
    }

    /// False at the end of the video; a failure ends the job and also answers true, because
    /// the job's end is then already decided.
    private func copyNextFrame(of work: PreparedRender, seconds: Double) -> Bool {
        gate.waitUntilInFront(unlessStopped: { self.hasStopped })
        guard !hasStopped, let sample = work.videoOutput.copyNextSampleBuffer() else { return false }
        do {
            try write(sample, from: work)
            reportProgress(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)) / seconds)
        } catch {
            fail(error)
        }
        return true
    }

    private func write(_ sample: CMSampleBuffer, from work: PreparedRender) throws {
        guard let pixels = CMSampleBufferGetImageBuffer(sample) else { return }
        guard let pool = work.adaptor.pixelBufferPool else {
            throw RenderSpecError(message: "The video encoder has no buffers.")
        }
        var output: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output)
        guard let output else { throw RenderSpecError(message: "Out of memory for a frame.") }
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        let frame = SourceFrame(pixels: pixels, orientation: work.orientation, timeMs: clipTimeMs(time))
        try drawInFront(frame, using: work.composer, into: output)
        guard work.adaptor.append(output, withPresentationTime: time) else {
            throw work.writer.error ?? RenderSpecError(message: "Couldn't write a frame.")
        }
    }

    /// Core Image draws nothing, and says nothing, when the app was sent to the background
    /// during the frame, so that frame is drawn again once the app is back in front.
    private func drawInFront(_ frame: SourceFrame, using composer: FrameComposer, into output: CVPixelBuffer) throws {
        repeat {
            gate.waitUntilInFront(unlessStopped: { self.hasStopped })
            try composer.render(frame, into: output)
        } while !gate.isInFront && !hasStopped
    }

    private func copyAudio(_ ready: PreparedRender) {
        guard let input = ready.audioInput else { return }
        input.requestMediaDataWhenReady(on: audioQueue) { [weak self] in
            guard let self else { return }
            while let work = self.currentWork(), let input = work.audioInput, let output = work.audioOutput,
                  input.isReadyForMoreMediaData {
                var reachedEnd = false
                autoreleasepool { reachedEnd = !self.copyNextSound(from: output, to: input, of: work) }
                if self.hasStopped { return }
                if reachedEnd {
                    self.endOfStream(reader: work.reader, input: input)
                    return
                }
            }
        }
    }

    private func copyNextSound(from output: AVAssetReaderTrackOutput, to input: AVAssetWriterInput, of work: PreparedRender) -> Bool {
        guard let sample = output.copyNextSampleBuffer() else { return false }
        if !input.append(sample) {
            fail(work.writer.error ?? RenderSpecError(message: "Couldn't write the sound."))
        }
        return true
    }

    /// A reader that failed also stops handing out samples; that is not the end of the clip.
    private func endOfStream(reader: AVAssetReader, input: AVAssetWriterInput) {
        if reader.status == .failed {
            fail(reader.error ?? RenderSpecError(message: "Couldn't read the video."))
            return
        }
        _ = whileRunning { input.markAsFinished() }
        streamEnded()
    }

    /// The writer is closed once the picture and the sound are both through.
    private func streamEnded() {
        _ = whileRunning {
            unfinishedStreams -= 1
            guard unfinishedStreams == 0, let writer = prepared?.writer else { return }
            writer.finishWriting { [weak self] in
                if writer.status == .completed {
                    self?.succeed()
                } else {
                    self?.fail(writer.error ?? RenderSpecError(message: "Export failed."))
                }
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
    /// What AAC-LC takes in: 16 to 48 kHz, one or two channels.
    private static let lowestRate = 16_000.0
    private static let highestRate = 48_000.0
    static let rateForChosenBitRate = 32_000.0

    let sampleRate: Double
    let channels: Int

    init(sampleRate: Double, channels: Int) {
        self.sampleRate = min(max(sampleRate, AudioFormat.lowestRate), AudioFormat.highestRate)
        self.channels = min(2, max(1, channels))
    }

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
