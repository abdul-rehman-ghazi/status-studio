import Foundation

/// What the Share Extension and the app agree on (spec FR-1, M26 task 3).
///
/// The extension copies a shared video into the App Group's `incoming/` folder, one folder per
/// share. A share being copied is `<id>.part`; it is renamed to `<id>` (holding the video under
/// its own name) once the copy is whole, so the app never reads half a video. A share that could
/// not be copied is `<id>.failed`, a small JSON file with a `code` and a `message`.
enum SharedIncoming {
    static let groupIdentifier = "group.com.hotmail.arehmananis.statusstudio"
    static let folderName = "incoming"
    static let unfinishedSuffix = ".part"
    static let failedSuffix = ".failed"

    /// Leaves room for the app's `<id>-` prefix inside the 255 bytes a file name may take.
    static let longestNameBytes = 200

    /// Nil when the App Group is not available: an app or extension that was not signed with it.
    static func folderInGroupContainer(fileManager: FileManager = .default) -> URL? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent(folderName, isDirectory: true)
    }

    /// The sender's file name, cut to what a file system accepts: never inside a character and
    /// keeping the extension, which the importer reads the format from.
    static func fileName(from displayName: String) -> String {
        let plainName = (displayName as NSString).lastPathComponent
        let name = plainName.isEmpty || plainName == "/" ? "video.mov" : plainName
        guard name.utf8.count > longestNameBytes else { return name }
        let fileExtension = (name as NSString).pathExtension
        let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
        let stem = String((name as NSString).deletingPathExtension)
        return truncated(stem, toBytes: longestNameBytes - suffix.utf8.count) + suffix
    }

    /// The code Dart maps to its error types: `no_space` or `copy_failed`.
    static func failureCode(of error: Error) -> String {
        let cocoa = error as NSError
        let outOfSpace = cocoa.domain == NSCocoaErrorDomain && cocoa.code == NSFileWriteOutOfSpaceError
        return outOfSpace ? "no_space" : "copy_failed"
    }

    private static func truncated(_ text: String, toBytes limit: Int) -> String {
        var kept = ""
        for character in text {
            if kept.utf8.count + String(character).utf8.count > limit { break }
            kept.append(character)
        }
        return kept
    }
}
