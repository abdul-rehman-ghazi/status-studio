import UIKit
import UniformTypeIdentifiers

/// The system's Share sheet entry for videos (spec FR-1). It copies the shared movie into the
/// App Group (`SharedIncoming`), asks the system to open Status Studio, and ends. The app picks
/// the copy up whenever it becomes active, so a share is not lost if opening the app fails.
final class ShareViewController: UIViewController {
    private static let appURL = URL(string: "statusstudio://shared")!

    private static let failureShownSeconds = 2.0

    /// The app's page and text colours for the phone's mode, like the launch screen: the
    /// extension can't read the theme chosen in the app (spec FR-32).
    private static let pageColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.075, blue: 0.067, alpha: 1)
            : UIColor(red: 0.961, green: 0.973, blue: 0.965, alpha: 1)
    }

    private static let textColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.933, green: 0.953, blue: 0.941, alpha: 1)
            : UIColor(red: 0.055, green: 0.075, blue: 0.067, alpha: 1)
    }

    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Self.pageColor
        showStatus("Opening in Status Studio…")
        stageSharedMovie()
    }

    private func showStatus(_ text: String) {
        statusLabel.text = text
        statusLabel.textColor = Self.textColor
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        guard statusLabel.superview == nil else { return }
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
    }

    private func stageSharedMovie() {
        guard let provider = movieProvider() else {
            return finish(reporting: ShareFailure(code: "copy_failed", message: "This isn't a video.", reachesApp: false))
        }
        provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] file, error in
            // The file is only ours inside this closure, so it is copied before returning.
            let outcome = Self.stage(file, loadError: error)
            DispatchQueue.main.async { self?.finish(reporting: outcome) }
        }
    }

    private func movieProvider() -> NSItemProvider? {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        return items
            .flatMap { $0.attachments ?? [] }
            .first { $0.hasItemConformingToTypeIdentifier(UTType.movie.identifier) }
    }

    /// Nil failure means the video is whole in the App Group.
    private static func stage(_ file: URL?, loadError: Error?) -> ShareFailure? {
        guard let incoming = SharedIncoming.folderInGroupContainer() else {
            return ShareFailure(
                code: "copy_failed",
                message: "Status Studio isn't set up to receive videos.",
                reachesApp: false
            )
        }
        do {
            guard let file else { throw loadError ?? CocoaError(.fileReadUnknown) }
            try copy(file, into: incoming)
            return nil
        } catch {
            return recordedFailure(of: error, in: incoming)
        }
    }

    /// The report for the app, and the words for the sheet. Without a report the app would open
    /// with nothing to show, so it is not opened.
    private static func recordedFailure(of error: Error, in incoming: URL) -> ShareFailure {
        let code = SharedIncoming.failureCode(of: error)
        let message = code == "no_space" ? "Not enough space on your phone." : error.localizedDescription
        let wasRecorded = record(code: code, message: message, in: incoming)
        return ShareFailure(code: code, message: message, reachesApp: wasRecorded)
    }

    private static func copy(_ file: URL, into incoming: URL) throws {
        let fileManager = FileManager.default
        let id = UUID().uuidString
        let unfinished = incoming.appendingPathComponent(id + SharedIncoming.unfinishedSuffix, isDirectory: true)
        try fileManager.createDirectory(at: unfinished, withIntermediateDirectories: true)
        do {
            let name = SharedIncoming.fileName(from: file.lastPathComponent)
            try fileManager.copyItem(at: file, to: unfinished.appendingPathComponent(name))
            try fileManager.moveItem(at: unfinished, to: incoming.appendingPathComponent(id, isDirectory: true))
        } catch {
            try? fileManager.removeItem(at: unfinished)
            throw error
        }
    }

    private static func record(code: String, message: String, in incoming: URL) -> Bool {
        let report = ["code": code, "message": message]
        guard let json = try? JSONSerialization.data(withJSONObject: report) else { return false }
        let target = incoming.appendingPathComponent(UUID().uuidString + SharedIncoming.failedSuffix)
        do {
            try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
            try json.write(to: target, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// A failure stays on screen for a moment, so the person can read it before the sheet closes.
    private func finish(reporting failure: ShareFailure?) {
        guard let failure else { return end(opening: true) }
        showStatus(failure.message)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.failureShownSeconds) { [weak self] in
            self?.end(opening: failure.reachesApp)
        }
    }

    private func end(opening openApp: Bool) {
        if openApp { openHostApp() }
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// An extension may not call `UIApplication.shared`, and `extensionContext.open` only works
    /// from a Today widget, so the app's `openURL:options:completionHandler:` is found along the
    /// responder chain. If the system refuses, the share still waits for the app (see above).
    private func openHostApp() {
        typealias OpenURL = @convention(c) (
            AnyObject, Selector, URL, [UIApplication.OpenExternalURLOptionsKey: Any], ((Bool) -> Void)?
        ) -> Void
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication, current.responds(to: selector) {
                let open = unsafeBitCast(current.method(for: selector), to: OpenURL.self)
                open(current, selector, Self.appURL, [:], nil)
                return
            }
            responder = current.next
        }
    }
}

private struct ShareFailure {
    let code: String
    let message: String

    /// Whether a `.failed` report was left for the app, which then tells Dart; without one,
    /// opening the app would show nothing.
    let reachesApp: Bool
}
