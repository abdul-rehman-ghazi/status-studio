package com.hotmail.arehmananis.statusstudio.videoin

import java.io.File
import java.io.IOException

private const val ACTION_SEND = "android.intent.action.SEND"
private const val ACTION_VIEW = "android.intent.action.VIEW"

// Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY, copied so JVM tests can use it.
private const val FLAG_LAUNCHED_FROM_HISTORY = 0x00100000

private const val MAX_FILE_NAME_BYTES = 255
private const val FREE_SPACE_MARGIN_BYTES = 50L * 1024 * 1024

private val extensionByMimeType = mapOf(
    "video/mp4" to "mp4",
    "video/quicktime" to "mov",
    "video/webm" to "webm",
    "video/x-matroska" to "mkv",
    "video/3gpp" to "3gp",
)

private val videoExtensions = setOf(
    "mp4", "m4v", "mov", "webm", "mkv", "3gp", "3g2", "avi", "mpg", "mpeg", "ts", "flv", "wmv",
)

/** The copy would not fit on the phone's storage. */
class InsufficientStorageException(message: String) : IOException(message)

/** Only a `SEND` or `VIEW` of a video counts: the intent filters also admit nothing else. */
fun isVideoShare(action: String?, mimeType: String?): Boolean {
    if (action != ACTION_SEND && action != ACTION_VIEW) return false
    return mimeType?.startsWith("video/") == true
}

/**
 * Whether the activity should look at its intent. Reopening the app from Recents replays the
 * original share with the history flag, and a restored activity still holds its old intent.
 */
fun shouldHandleIntent(flags: Int, restoredBySystem: Boolean): Boolean {
    if (restoredBySystem) return false
    return flags and FLAG_LAUNCHED_FROM_HISTORY == 0
}

/**
 * The name the copy gets in the staging folder: [uniquePrefix] keeps two shares of `clip.mp4`
 * apart. The sender chose the display name, so separators and `..` are dropped, the name is cut
 * to what a file system accepts (255 bytes, never inside a character), and a name without a
 * video extension gets one, because the importer reads the extension off the path.
 */
fun stagedFileName(displayName: String?, mimeType: String?, uniquePrefix: String): String {
    val prefix = "${uniquePrefix}_"
    val cleanName = lastPathSegmentOf(displayName)
    val name = if (cleanName == null) fallbackName(mimeType) else withVideoExtension(cleanName, mimeType)
    val room = MAX_FILE_NAME_BYTES - prefix.toByteArray().size
    return prefix + fitInBytes(name, room)
}

private fun lastPathSegmentOf(displayName: String?): String? {
    val segment = displayName
        ?.substringAfterLast('/')
        ?.substringAfterLast('\\')
        ?.filter { !it.isISOControl() }
        ?.trim()
    if (segment.isNullOrEmpty() || segment == "." || segment == "..") return null
    return segment
}

private fun fallbackName(mimeType: String?): String = "video.${extensionFor(mimeType)}"

private fun extensionFor(mimeType: String?): String = extensionByMimeType[mimeType] ?: "mp4"

private fun withVideoExtension(name: String, mimeType: String?): String {
    val extension = name.substringAfterLast('.', "").lowercase()
    if (extension in videoExtensions) return name
    return "$name.${extensionFor(mimeType)}"
}

/** Cuts the base name, not the extension, so the result still ends in `.mp4`. */
private fun fitInBytes(name: String, maxBytes: Int): String {
    if (name.toByteArray().size <= maxBytes) return name
    val extension = name.substringAfterLast('.')
    val dotAndExtension = ".$extension"
    val base = name.removeSuffix(dotAndExtension)
    val baseRoom = maxBytes - dotAndExtension.toByteArray().size
    return truncateUtf8(base, baseRoom) + dotAndExtension
}

private fun truncateUtf8(text: String, maxBytes: Int): String {
    var usedBytes = 0
    val kept = StringBuilder()
    var index = 0
    while (index < text.length) {
        val codePoint = text.codePointAt(index)
        val character = String(Character.toChars(codePoint))
        usedBytes += character.toByteArray().size
        if (usedBytes > maxBytes) break
        kept.append(character)
        index += character.length
    }
    return kept.toString()
}

/** Whether [sizeBytes] fits in [usableBytes] and leaves a margin for the rest of the app. */
fun hasRoomFor(sizeBytes: Long?, usableBytes: Long): Boolean {
    if (sizeBytes == null || sizeBytes < 0) return true
    return usableBytes - sizeBytes >= FREE_SPACE_MARGIN_BYTES
}

/** Resolves symbolic links and `..`, so a path can't claim to be elsewhere. */
fun isInsideDirectory(candidate: File, directory: File): Boolean {
    val folder = directory.canonicalFile
    return candidate.canonicalFile.startsWith(folder)
}

/** The copy ran out of space; the message text is all Java's `IOException` gives. */
fun isOutOfSpace(message: String?): Boolean =
    message?.contains("ENOSPC") == true || message?.contains("No space left", ignoreCase = true) == true

/** The code Dart maps to its error types: `no_space` or `copy_failed`. */
fun failureCodeOf(error: Exception): String {
    if (error is InsufficientStorageException || isOutOfSpace(error.message)) return "no_space"
    return "copy_failed"
}

private val webLinkPattern = Regex("""https?://[^\s/?#]+\.[^\s/?#]+\S*""", RegexOption.IGNORE_CASE)

/**
 * YouTube, Facebook and Instagram share text such as "Title https://youtu.be/…", so the first
 * `http` or `https` link is picked out of it (spec FR-35, FR-50).
 */
fun firstWebLink(sharedText: String?): String? =
    sharedText?.let { webLinkPattern.find(it)?.value }
