package com.hotmail.arehmananis.statusstudio.videoin

private const val ACTION_SEND = "android.intent.action.SEND"
private const val ACTION_VIEW = "android.intent.action.VIEW"

private val extensionByMimeType = mapOf(
    "video/mp4" to "mp4",
    "video/quicktime" to "mov",
    "video/webm" to "webm",
    "video/x-matroska" to "mkv",
    "video/3gpp" to "3gp",
)

/** Only a `SEND` or `VIEW` of a video counts: the intent filters also admit nothing else. */
fun isVideoShare(action: String?, mimeType: String?): Boolean {
    if (action != ACTION_SEND && action != ACTION_VIEW) return false
    return mimeType?.startsWith("video/") == true
}

/**
 * The name the copy gets in the staging folder. The timestamp keeps two shares of
 * `clip.mp4` apart; separators are dropped because the sender chose the display name.
 */
fun stagedFileName(displayName: String?, mimeType: String?, nowMillis: Long): String {
    val safeName = displayName?.substringAfterLast('/')?.substringAfterLast('\\')?.trim()
    val name = if (safeName.isNullOrEmpty()) fallbackName(mimeType) else safeName
    return "${nowMillis}_$name"
}

private fun fallbackName(mimeType: String?): String =
    "video.${extensionByMimeType[mimeType] ?: "mp4"}"

/** The copy ran out of space; the message text is all Java's `IOException` gives. */
fun isOutOfSpace(message: String?): Boolean =
    message?.contains("ENOSPC") == true || message?.contains("No space left", ignoreCase = true) == true
