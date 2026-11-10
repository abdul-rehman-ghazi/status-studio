import Foundation
import UniformTypeIdentifiers

/// One finished share, as Dart's `IncomingVideoSource` reads it.
struct SharedVideoFile {
    let path: String
    let displayName: String
    let mimeType: String
}

enum ShareOutcome {
    case video(SharedVideoFile)
    case failure(code: String, message: String)
}

private let staleAfterSeconds: TimeInterval = 24 * 60 * 60

/// Picks up what the Share Extension left in the App Group and moves each video into the app's
/// own `incoming` folder (`Application Support/incoming`), where Dart's importer expects staged
/// videos and moves them on into `sources/<videoId>/` (spec FR-1).
///
/// Not thread-safe: `collect` and `deleteStaleCopies` run on one queue, never the main thread (a
/// video is a large file); `freeBytes` only reads and may be asked from anywhere.
final class ShareInbox {
    private let groupFolder: URL?
    private let stagingFolder: URL
    private let fileManager: FileManager

    init(groupFolder: URL?, stagingFolder: URL, fileManager: FileManager = .default) {
        self.groupFolder = groupFolder
        self.stagingFolder = stagingFolder
        self.fileManager = fileManager
    }

    static func forThisApp() -> ShareInbox {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ShareInbox(
            groupFolder: SharedIncoming.folderInGroupContainer(),
            stagingFolder: support.appendingPathComponent("incoming", isDirectory: true)
        )
    }

    /// Every finished share since the last call. A share that cannot be moved is a failure, so
    /// Dart tells the user, and its leftovers are deleted.
    func collect() -> [ShareOutcome] {
        guard let groupFolder, let entries = try? fileManager.contentsOfDirectory(
            at: groupFolder,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return entries.compactMap { outcome(for: $0) }
    }

    /// Copies nobody imported (the user ignored the share) would otherwise stay for good.
    func deleteStaleCopies() {
        let oldestKept = Date().addingTimeInterval(-staleAfterSeconds)
        for folder in [groupFolder, stagingFolder].compactMap({ $0 }) {
            deleteEntries(in: folder, modifiedBefore: oldestKept)
        }
    }

    /// The bytes free for this app, or nil when the system cannot say.
    func freeBytes() -> Int64? {
        let key = URLResourceKey.volumeAvailableCapacityForImportantUsageKey
        let values = try? stagingFolder.deletingLastPathComponent().resourceValues(forKeys: [key])
        guard let free = values?.volumeAvailableCapacityForImportantUsage, free > 0 else { return nil }
        return free
    }

    private func outcome(for entry: URL) -> ShareOutcome? {
        let name = entry.lastPathComponent
        if name.hasSuffix(SharedIncoming.unfinishedSuffix) { return nil }
        if name.hasSuffix(SharedIncoming.failedSuffix) { return failure(in: entry) }
        return video(in: entry)
    }

    private func failure(in entry: URL) -> ShareOutcome {
        defer { try? fileManager.removeItem(at: entry) }
        let report = (try? Data(contentsOf: entry))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
        return .failure(
            code: report?["code"] ?? "copy_failed",
            message: report?["message"] ?? "Couldn't copy the video."
        )
    }

    private func video(in shareFolder: URL) -> ShareOutcome? {
        defer { try? fileManager.removeItem(at: shareFolder) }
        guard let file = try? fileManager.contentsOfDirectory(
            at: shareFolder,
            includingPropertiesForKeys: nil
        ).first else { return nil }
        do {
            let staged = try move(file, intoStagingWithPrefix: shareFolder.lastPathComponent)
            return .video(SharedVideoFile(
                path: staged.path,
                displayName: file.lastPathComponent,
                mimeType: mimeType(forFileNamed: file.lastPathComponent)
            ))
        } catch {
            return .failure(code: SharedIncoming.failureCode(of: error), message: error.localizedDescription)
        }
    }

    private func move(_ file: URL, intoStagingWithPrefix prefix: String) throws -> URL {
        try fileManager.createDirectory(at: stagingFolder, withIntermediateDirectories: true)
        let target = stagingFolder.appendingPathComponent("\(prefix)-\(file.lastPathComponent)")
        do {
            try fileManager.moveItem(at: file, to: target)
        } catch {
            // Two containers can sit on different volumes; then a move must be a copy.
            try? fileManager.removeItem(at: target)
            try fileManager.copyItem(at: file, to: target)
        }
        // A moved or cloned file keeps the date the video was recorded, which would make a share
        // from last week look stale at once.
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)
        return target
    }

    private func deleteEntries(in folder: URL, modifiedBefore oldestKept: Date) {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for entry in entries {
            let modified = try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, modified < oldestKept { try? fileManager.removeItem(at: entry) }
        }
    }
}

/// Dart refuses anything that is not `video/*`; an extension iOS cannot name is still a movie,
/// because the extension only accepts movies.
func mimeType(forFileNamed fileName: String) -> String {
    let fileExtension = (fileName as NSString).pathExtension
    let named = UTType(filenameExtension: fileExtension)?.preferredMIMEType
    guard let named, named.hasPrefix("video/") else { return "video/quicktime" }
    return named
}
