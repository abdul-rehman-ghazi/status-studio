import Flutter
import UIKit

/// `status_studio/video_in`: videos other apps share into this one through the Share Extension
/// (spec FR-1), with the same protocol as Android's `VideoInChannel`. Dart calls `listen()`,
/// which returns what arrived while Dart wasn't listening (the share that launched the app);
/// from then on `incomingVideo` and `incomingVideoFailed` are pushed as they happen, until
/// `stopListening()`. Each kept entry is `{method, arguments}`. `freeBytes()` is the room left
/// for the app's files.
final class VideoInChannel {
    private let channel: FlutterMethodChannel
    private let inbox: ShareInbox
    private let worker = DispatchQueue(label: "status_studio.video_in", qos: .userInitiated)
    private lazy var deliveries = ShareDeliveries { [weak channel] method, arguments in
        channel?.invokeMethod(method, arguments: arguments)
    }

    init(messenger: FlutterBinaryMessenger, inbox: ShareInbox = .forThisApp()) {
        channel = FlutterMethodChannel(name: "status_studio/video_in", binaryMessenger: messenger)
        self.inbox = inbox
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
        // The extension may open the app, or the user may open it by hand: either way the
        // share waits in the App Group until the app is active.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.collectShares() }
        worker.async { [inbox] in inbox.deleteStaleCopies() }
        collectShares()
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "listen":
            result(deliveries.startListening())
        case "stopListening":
            deliveries.stopListening()
            result(nil)
        case "freeBytes":
            replyWithFreeBytes(result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// The file system reports nothing when it can't tell, which is not the same as a full
    /// phone, so Dart is told the answer is unknown and decides what to do.
    private func replyWithFreeBytes(_ result: FlutterResult) {
        guard let freeBytes = inbox.freeBytes() else {
            result(FlutterError(
                code: "storage_unknown",
                message: "The free space of the data folder is unknown.",
                details: nil
            ))
            return
        }
        result(freeBytes)
    }

    private func collectShares() {
        worker.async { [inbox, weak self] in
            let outcomes = inbox.collect()
            guard !outcomes.isEmpty else { return }
            DispatchQueue.main.async {
                for outcome in outcomes { self?.deliver(outcome) }
            }
        }
    }

    private func deliver(_ outcome: ShareOutcome) {
        switch outcome {
        case .video(let video):
            deliveries.deliver(method: "incomingVideo", arguments: [
                "path": video.path,
                "displayName": video.displayName,
                "mimeType": video.mimeType,
            ])
        case .failure(let code, let message):
            deliveries.deliver(method: "incomingVideoFailed", arguments: [
                "code": code,
                "message": message,
            ])
        }
    }
}
