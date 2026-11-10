import AVFoundation
import Flutter

/// `status_studio/render` (`start`, `cancel`, and `convert`, which answers when the file is
/// written) and `status_studio/render/events`, which sends
/// `{type: progress, value}`, `{type: done, path}` and `{type: error, message}`: the same
/// protocol as Android's `RenderChannel`, taking the map Dart's `renderSpecFor` builds.
final class RenderChannel: NSObject, FlutterStreamHandler {
    private let renderer = ReelRenderer()
    private var events: FlutterEventSink?

    init(messenger: FlutterBinaryMessenger) {
        super.init()
        let methods = FlutterMethodChannel(name: "status_studio/render", binaryMessenger: messenger)
        methods.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
        FlutterEventChannel(name: "status_studio/render/events", binaryMessenger: messenger)
            .setStreamHandler(self)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            start(call.arguments, result: result)
        case "convert":
            convert(call.arguments, result: result)
        case "cancel":
            renderer.cancel()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func start(_ arguments: Any?, result: FlutterResult) {
        guard !renderer.isBusy else {
            result(FlutterError(code: "busy", message: "A render is already running.", details: nil))
            return
        }
        guard let map = arguments as? [String: Any] else {
            result(FlutterError(code: "bad_spec", message: "The render spec must be a map.", details: nil))
            return
        }
        do {
            renderer.start(try RenderSpec(map: map), listener: listener)
            result(nil)
        } catch {
            result(FlutterError(code: "bad_spec", message: error.localizedDescription, details: nil))
        }
    }

    private func convert(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let map = arguments as? [String: Any],
              let inputPath = map["inputPath"] as? String,
              let outputPath = map["outputPath"] as? String
        else {
            result(FlutterError(code: "bad_spec", message: "convert needs inputPath and outputPath.", details: nil))
            return
        }
        VideoConverter.convert(
            input: URL(fileURLWithPath: inputPath),
            output: URL(fileURLWithPath: outputPath)
        ) { message in
            DispatchQueue.main.async {
                result(message.map { FlutterError(code: "convert_failed", message: $0, details: nil) })
            }
        }
    }

    private var listener: ReelRenderer.Listener {
        ReelRenderer.Listener(
            onProgress: { [weak self] fraction in self?.events?(["type": "progress", "value": fraction]) },
            onDone: { [weak self] path in self?.events?(["type": "done", "path": path]) },
            onError: { [weak self] message in self?.events?(["type": "error", "message": message]) }
        )
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.events = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        events = nil
        return nil
    }
}

/// Converts a video the bundled FFmpeg can't decode (AV1) to H.264 (spec FR-1, M31).
/// AVFoundation decodes AV1 only on A17 Pro and M3 chips or newer, so on most iPhones the
/// export fails and the completion gets its message.
private enum VideoConverter {
    /// Calls `completion` with nil when the file is written, or with why it wasn't.
    static func convert(input: URL, output: URL, completion: @escaping (String?) -> Void) {
        guard let export = AVAssetExportSession(
            asset: AVURLAsset(url: input),
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            completion("This phone can't convert the video.")
            return
        }
        export.outputURL = output
        export.outputFileType = .mp4
        export.exportAsynchronously {
            guard export.status == .completed else {
                try? FileManager.default.removeItem(at: output)
                completion(export.error?.localizedDescription ?? "Conversion failed.")
                return
            }
            completion(nil)
        }
    }
}
