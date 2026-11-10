import Flutter
import UIKit
import UserNotifications

/// `status_studio/system`: `openAppSettings`, the app's page in system Settings, and
/// `beginBackgroundTask` / `endBackgroundTask`, which keep scripts and exports going for the
/// short time iOS allows after the user leaves (spec FR-16). iOS has no foreground service.
final class SystemChannel {
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    init(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "status_studio/system", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
        switch call.method {
        case "openAppSettings":
            openAppSettings()
            result(nil)
        case "beginBackgroundTask":
            beginBackgroundTask()
            result(nil)
        case "endBackgroundTask":
            endBackgroundTask()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Does nothing while a task is already running, so the many progress updates of one job
    /// ask once.
    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "status_studio.work") { [weak self] in
            // The grace period is over; the work stops until the user comes back.
            PausedNotice.post()
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}

/// Tells the user that work was cut short. Nothing is shown if they never allowed notifications.
private enum PausedNotice {
    static func post() {
        let content = UNMutableNotificationContent()
        content.title = "Work paused"
        content.body = "Open Status Studio to carry on. A script resumes from its last saved piece."
        let request = UNNotificationRequest(identifier: "status_studio.paused", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
