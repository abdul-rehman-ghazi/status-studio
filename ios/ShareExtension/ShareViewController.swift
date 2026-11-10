import UIKit
import UniformTypeIdentifiers

/// The system's Share sheet entry for videos (spec FR-1). It copies the shared movie into the
/// App Group (`SharedIncoming`), asks the system to open Status Studio, and ends. The app picks
/// the copy up whenever it becomes active, so a share is not lost if opening the app fails.
final class ShareViewController: UIViewController {
    private static let appURL = URL(string: "statusstudio://shared")!

    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.055, green: 0.075, blue: 0.067, alpha: 1)
        showStatus("Opening in Status Studio…")
        stageSharedMovie()
    }

    private func showStatus(_ text: String) {
        statusLabel.text = text
        statusLabel.textColor = .white
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
            return finish(reporting: ShareFailure(code: "copy_failed", message: "This isn't a video."))
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
            return ShareFailure(code: "copy_failed", message: "Status Studio isn't set up to receive videos.")
        }
        do {
            guard let file else { throw loadError ?? CocoaError(.fileReadUnknown) }
            try copy(file, into: incoming)
            return nil
        } catch {
            let failure = ShareFailure(code: SharedIncoming.failureCode(of: error), message: error.localizedDescription)
            record(failure, in: incoming)
            return failure
        }
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

    private static func record(_ failure: ShareFailure, in incoming: URL) {
        let report = ["code": failure.code, "message": failure.message]
        guard let json = try? JSONSerialization.data(withJSONObject: report) else { return }
        try? FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        let target = incoming.appendingPathComponent(UUID().uuidString + SharedIncoming.failedSuffix)
        try? json.write(to: target)
    }

    private func finish(reporting failure: ShareFailure?) {
        if let failure, failure.code == "no_space" {
            showStatus("There isn't enough free space for this video.")
        }
        openHostApp()
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
}
