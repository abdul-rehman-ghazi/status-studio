package com.hotmail.arehmananis.statusstudio.render

import android.content.Context
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import java.io.File

/**
 * Converts a video the bundled FFmpeg can't decode (AV1) to H.264 video and AAC audio, with no
 * other change (spec FR-1, M31). Android decodes AV1 in software from Android 10; on older
 * phones the export fails and [Listener.onError] says so. Must be used from the main thread.
 */
@OptIn(markerClass = [UnstableApi::class])
class VideoConverter(private val context: Context) {
    interface Listener {
        fun onDone()

        fun onError(message: String)
    }

    // Held until each export ends, so a running Transformer is never left unreferenced.
    private val running = mutableSetOf<Transformer>()

    /** Throws any exception Media3 raises for an input it rejects at once. */
    fun convert(inputPath: String, outputPath: String, listener: Listener) {
        val transformer = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .build()
        transformer.addListener(completionListener(transformer, outputPath, listener))
        val mediaItem = MediaItem.fromUri(Uri.fromFile(File(inputPath)))
        transformer.start(EditedMediaItem.Builder(mediaItem).build(), outputPath)
        running.add(transformer)
    }

    private fun completionListener(transformer: Transformer, outputPath: String, listener: Listener) =
        object : Transformer.Listener {
            override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                running.remove(transformer)
                listener.onDone()
            }

            override fun onError(
                composition: Composition,
                exportResult: ExportResult,
                exportException: ExportException,
            ) {
                running.remove(transformer)
                File(outputPath).delete()
                listener.onError(exportException.message ?: "Conversion failed.")
            }
        }
}
