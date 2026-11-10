import Flutter

/// `status_studio/render` (`start`, `cancel`) and `status_studio/render/events`, which sends
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

    private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
        switch call.method {
        case "start":
            start(call.arguments, result: result)
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
