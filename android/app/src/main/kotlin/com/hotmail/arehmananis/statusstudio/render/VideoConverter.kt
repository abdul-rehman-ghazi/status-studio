package com.hotmail.arehmananis.statusstudio.render

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import java.io.File

private const val PROGRESS_INTERVAL_MS = 250L

/**
 * Converts a video the bundled FFmpeg can't decode (AV1) to H.264 video and AAC audio, with no
 * other change (spec FR-1, M31). Android decodes AV1 in software from Android 10; on older
 * phones the export fails and [Listener.onError] says so. Must be used from the main thread.
 */
@OptIn(markerClass = [UnstableApi::class])
class VideoConverter(private val context: Context) {
    interface Listener {
        fun onProgress(fraction: Double)

        fun onDone()

        fun onError(message: String)
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    // Held until each export ends, so a running Transformer is never left unreferenced; the
    // value is its progress poll.
    private val running = mutableMapOf<Transformer, Runnable>()

    /** Throws any exception Media3 raises for an input it rejects at once. */
    fun convert(inputPath: String, outputPath: String, listener: Listener) {
        val transformer = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .build()
        transformer.addListener(completionListener(transformer, outputPath, listener))
        val mediaItem = MediaItem.fromUri(Uri.fromFile(File(inputPath)))
        transformer.start(EditedMediaItem.Builder(mediaItem).build(), outputPath)
        val poll = progressPoll(transformer, listener)
        running[transformer] = poll
        mainHandler.post(poll)
    }

    private fun finish(transformer: Transformer) {
        running.remove(transformer)?.let { mainHandler.removeCallbacks(it) }
    }

    private fun progressPoll(transformer: Transformer, listener: Listener): Runnable {
        val holder = ProgressHolder()
        return object : Runnable {
            override fun run() {
                if (transformer.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                    listener.onProgress(holder.progress / 100.0)
                }
                mainHandler.postDelayed(this, PROGRESS_INTERVAL_MS)
            }
        }
    }

    private fun completionListener(transformer: Transformer, outputPath: String, listener: Listener) =
        object : Transformer.Listener {
            override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                finish(transformer)
                listener.onDone()
            }

            override fun onError(
                composition: Composition,
                exportResult: ExportResult,
                exportException: ExportException,
            ) {
                finish(transformer)
                File(outputPath).delete()
                listener.onError(exportException.message ?: "Conversion failed.")
            }
        }
}
