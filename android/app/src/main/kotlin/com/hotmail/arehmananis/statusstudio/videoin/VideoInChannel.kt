package com.hotmail.arehmananis.statusstudio.videoin

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

private const val STAGING_FOLDER = "incoming"
private const val STALE_AFTER_MILLIS = 24L * 60 * 60 * 1000

/**
 * `status_studio/video_in`: videos other apps share into this one (spec FR-1).
 *
 * The shared content URI is only readable for a while, so each share is streamed into
 * `files/incoming/` at once, off the main thread. Dart's importer later moves the copy
 * into `sources/<videoId>/`. Dart calls `listen()` once: it returns what arrived before
 * Dart was ready (the launch share), and from then on `incomingVideo` and
 * `incomingVideoFailed` are pushed as they happen. Each queued entry is
 * `{method, arguments}`.
 */
class VideoInChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "status_studio/video_in")
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val stagingFolder = File(context.filesDir, STAGING_FOLDER)

    // Both touched on the main thread only.
    private val waiting = mutableListOf<Map<String, Any?>>()
    private var dartListening = false

    init {
        channel.setMethodCallHandler(this)
        worker.execute { deleteStaleCopies() }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listen" -> {
                dartListening = true
                result.success(waiting.toList())
                waiting.clear()
            }
            "stopListening" -> {
                dartListening = false
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Called with the launch intent and again from `onNewIntent`. Ignores anything but a video. */
    fun receive(intent: Intent?) {
        if (intent == null || !isVideoShare(intent.action, intent.type)) return
        val sharedUri = sharedUriOf(intent) ?: return
        val mimeType = intent.type
        worker.execute {
            val outcome = try {
                "incomingVideo" to stage(sharedUri, mimeType)
            } catch (error: IOException) {
                "incomingVideoFailed" to failure(error)
            } catch (error: SecurityException) {
                "incomingVideoFailed" to mapOf("code" to "copy_failed", "message" to error.message)
            }
            mainHandler.post { deliver(outcome.first, outcome.second) }
        }
    }

    private fun deliver(method: String, arguments: Map<String, Any?>) {
        if (dartListening) {
            channel.invokeMethod(method, arguments)
            return
        }
        waiting.add(mapOf("method" to method, "arguments" to arguments))
    }

    private fun stage(sharedUri: Uri, mimeType: String?): Map<String, Any?> {
        val displayName = displayNameOf(sharedUri)
        stagingFolder.mkdirs()
        val copy = File(stagingFolder, stagedFileName(displayName, mimeType, System.currentTimeMillis()))
        try {
            copyStreaming(sharedUri, copy)
        } catch (error: IOException) {
            copy.delete()
            throw error
        }
        return mapOf(
            "path" to copy.path,
            "displayName" to (displayName ?: copy.name),
            "mimeType" to mimeType,
        )
    }

    private fun copyStreaming(source: Uri, target: File) {
        val input = context.contentResolver.openInputStream(source)
            ?: throw IOException("Can't open the shared video.")
        input.use { stream -> target.outputStream().use { stream.copyTo(it) } }
    }

    private fun displayNameOf(uri: Uri): String? {
        if (uri.scheme != "content") return uri.lastPathSegment
        val columns = arrayOf(OpenableColumns.DISPLAY_NAME)
        val cursor = context.contentResolver.query(uri, columns, null, null, null) ?: return null
        return cursor.use { if (it.moveToFirst()) it.getString(0) else null }
    }

    private fun failure(error: IOException): Map<String, Any?> {
        val code = if (isOutOfSpace(error.message)) "no_space" else "copy_failed"
        return mapOf("code" to code, "message" to error.message)
    }

    private fun sharedUriOf(intent: Intent): Uri? {
        if (intent.action == Intent.ACTION_VIEW) return intent.data
        return if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
        }
    }

    /** Copies nobody imported (the user ignored the share) would otherwise stay for good. */
    private fun deleteStaleCopies() {
        val oldestKept = System.currentTimeMillis() - STALE_AFTER_MILLIS
        stagingFolder.listFiles()?.filter { it.lastModified() < oldestKept }?.forEach { it.delete() }
    }
}
