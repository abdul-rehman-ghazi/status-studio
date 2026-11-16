package com.hotmail.arehmananis.statusstudio.videoin

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import androidx.core.content.IntentCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

private const val STAGING_FOLDER = "incoming"
private const val STALE_AFTER_MILLIS = 24L * 60 * 60 * 1000

private class SharedFileDetails(val displayName: String?, val sizeBytes: Long?)

/**
 * `status_studio/video_in`: videos other apps share into this one (spec FR-1).
 *
 * The shared content URI is only readable for a while, so each share is streamed into
 * `files/incoming/` at once, off the main thread. Dart's importer later moves the copy
 * into `sources/<videoId>/`. Dart calls `listen()`: it returns what arrived while Dart
 * wasn't listening (the launch share), and from then on `incomingVideo` and
 * `incomingVideoFailed` are pushed as they happen, until `stopListening()`. Each kept
 * entry is `{method, arguments}`.
 */
class VideoInChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "status_studio/video_in")
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val stagingFolder = File(context.filesDir, STAGING_FOLDER)
    private val stageCounter = AtomicLong()
    private val deliveries = ShareDeliveries { method, arguments ->
        channel.invokeMethod(method, arguments)
    }

    // Main thread only.
    private var disposed = false

    init {
        channel.setMethodCallHandler(this)
        worker.execute { deleteStaleCopies() }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listen" -> result.success(deliveries.startListening())
            "stopListening" -> {
                deliveries.stopListening()
                result.success(null)
            }
            "freeBytes" -> replyWithFreeBytes(result)
            else -> result.notImplemented()
        }
    }

    /**
     * The file system reports 0 when it can't tell, which is not the same as a full phone,
     * so Dart is told the answer is unknown and decides what to do.
     */
    private fun replyWithFreeBytes(result: MethodChannel.Result) {
        val freeBytes = context.filesDir.usableSpace
        if (freeBytes <= 0L) {
            result.error("storage_unknown", "The free space of the data folder is unknown.", null)
            return
        }
        result.success(freeBytes)
    }

    /**
     * Called with the launch intent and again from `onNewIntent`. Returns whether the intent
     * is a video share that is now being copied, so the caller can mark it as handled.
     */
    fun receive(intent: Intent?): Boolean {
        if (intent == null || disposed) return false
        if (receiveLink(intent)) return true
        val mimeType = mimeTypeOf(intent)
        if (!isVideoShare(intent.action, mimeType)) return false
        val sharedUri = sharedUriOf(intent) ?: return false
        worker.execute {
            val outcome = stageOutcome(sharedUri, mimeType)
            mainHandler.post { if (!disposed) deliveries.deliver(outcome.first, outcome.second) }
        }
        return true
    }

    /** A web link shared as text (spec FR-35, FR-50); text without one is left alone. */
    private fun receiveLink(intent: Intent): Boolean {
        if (intent.action != Intent.ACTION_SEND || intent.type != "text/plain") return false
        val link = firstWebLink(intent.getStringExtra(Intent.EXTRA_TEXT)) ?: return false
        deliveries.deliver("incomingLink", mapOf("link" to link))
        return true
    }

    /** Stops the worker; the engine this channel belongs to is going away. */
    fun dispose() {
        disposed = true
        worker.shutdownNow()
        channel.setMethodCallHandler(null)
    }

    /** `resolveType` asks the provider when the intent carries no type of its own. */
    private fun mimeTypeOf(intent: Intent): String? =
        try {
            intent.resolveType(context)
        } catch (error: RuntimeException) {
            intent.type
        }

    private fun stageOutcome(sharedUri: Uri, mimeType: String?): Pair<String, Map<String, Any?>> =
        try {
            "incomingVideo" to stage(sharedUri, mimeType)
        } catch (error: Exception) {
            "incomingVideoFailed" to failure(error)
        }

    private fun stage(sharedUri: Uri, mimeType: String?): Map<String, Any?> {
        refuseOwnFiles(sharedUri)
        val details = detailsOf(sharedUri)
        stagingFolder.mkdirs()
        requireRoomFor(details.sizeBytes)
        val copy = File(stagingFolder, stagedFileName(details.displayName, mimeType, nextPrefix()))
        copyStreaming(sharedUri, copy)
        return mapOf(
            "path" to copy.path,
            "displayName" to (details.displayName ?: copy.name),
            "mimeType" to mimeType,
        )
    }

    private fun nextPrefix(): String = "${System.currentTimeMillis()}-${stageCounter.incrementAndGet()}"

    /** Another app could point a `file` URI at our database or keys. */
    private fun refuseOwnFiles(uri: Uri) {
        val path = uri.path
        if (uri.scheme != "file" || path == null) return
        if (isInsideDirectory(File(path), context.dataDir)) {
            throw SecurityException("Won't read the app's own files.")
        }
    }

    private fun requireRoomFor(sizeBytes: Long?) {
        if (hasRoomFor(sizeBytes, stagingFolder.usableSpace)) return
        throw InsufficientStorageException("Not enough free space for this video.")
    }

    private fun copyStreaming(source: Uri, target: File) {
        try {
            val input = context.contentResolver.openInputStream(source)
                ?: throw IOException("Can't open the shared video.")
            input.use { stream -> target.outputStream().use { stream.copyTo(it) } }
        } catch (error: Exception) {
            target.delete()
            throw error
        }
    }

    private fun detailsOf(uri: Uri): SharedFileDetails {
        if (uri.scheme != "content") return SharedFileDetails(uri.lastPathSegment, null)
        val columns = arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val cursor = context.contentResolver.query(uri, columns, null, null, null)
            ?: return SharedFileDetails(null, null)
        return cursor.use {
            if (!it.moveToFirst()) return@use SharedFileDetails(null, null)
            val nameColumn = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            val sizeColumn = it.getColumnIndex(OpenableColumns.SIZE)
            SharedFileDetails(
                displayName = if (nameColumn >= 0) it.getString(nameColumn) else null,
                sizeBytes = if (sizeColumn >= 0 && !it.isNull(sizeColumn)) it.getLong(sizeColumn) else null,
            )
        }
    }

    private fun failure(error: Exception): Map<String, Any?> =
        mapOf("code" to failureCodeOf(error), "message" to (error.message ?: "Couldn't copy the video."))

    private fun sharedUriOf(intent: Intent): Uri? {
        val explicitUri = if (intent.action == Intent.ACTION_VIEW) {
            intent.data
        } else {
            IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
        }
        return explicitUri ?: firstClipUri(intent)
    }

    private fun firstClipUri(intent: Intent): Uri? {
        val clip = intent.clipData ?: return null
        return if (clip.itemCount > 0) clip.getItemAt(0).uri else null
    }

    /** Copies nobody imported (the user ignored the share) would otherwise stay for good. */
    private fun deleteStaleCopies() {
        val oldestKept = System.currentTimeMillis() - STALE_AFTER_MILLIS
        stagingFolder.listFiles()?.filter { it.lastModified() < oldestKept }?.forEach { it.delete() }
    }
}
