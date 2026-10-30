package com.hotmail.arehmananis.statusstudio.render

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.Crop
import androidx.media3.effect.GaussianBlurWithFrameOverlaid
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import java.io.File

private const val PROGRESS_INTERVAL_MS = 250L

/**
 * Renders one reel at a time with Media3 Transformer: trim, frame, overlay, then hardware
 * H.264/AAC (spec §5, FR-9). Must be used from the main thread.
 */
@OptIn(markerClass = [UnstableApi::class])
class ReelRenderer(private val context: Context) {
    interface Listener {
        fun onProgress(fraction: Double)

        fun onDone(path: String)

        fun onError(message: String)
    }

    private class Running(val transformer: Transformer, val outputPath: String, val poll: Runnable)

    private val mainHandler = Handler(Looper.getMainLooper())
    private var running: Running? = null

    val isBusy: Boolean
        get() = running != null

    /** Throws [IllegalArgumentException] when the overlay can't be read. */
    fun start(spec: RenderSpec, listener: Listener) {
        check(running == null) { "A render is already running." }
        val overlay = BitmapFactory.decodeFile(spec.overlayPath)
            ?: throw IllegalArgumentException("Couldn't read the overlay ${spec.overlayPath}.")
        val transformer = Transformer.Builder(context)
            .setVideoMimeType(spec.videoMimeType)
            .setAudioMimeType(spec.audioMimeType)
            .addListener(completionListener(listener))
            .build()
        val poll = progressPoll(transformer, listener)
        running = Running(transformer, spec.outputPath, poll)
        transformer.start(editedMediaItem(spec, overlay), spec.outputPath)
        mainHandler.post(poll)
    }

    /** Stops the render and deletes the partial file (FR-9). */
    fun cancel() {
        val current = finish() ?: return
        current.transformer.cancel()
        File(current.outputPath).delete()
    }

    private fun finish(): Running? {
        val current = running ?: return null
        mainHandler.removeCallbacks(current.poll)
        running = null
        return current
    }

    private fun completionListener(listener: Listener) =
        object : Transformer.Listener {
            override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                val done = finish() ?: return
                listener.onDone(done.outputPath)
            }

            override fun onError(
                composition: Composition,
                exportResult: ExportResult,
                exportException: ExportException,
            ) {
                val failed = finish() ?: return
                File(failed.outputPath).delete()
                listener.onError(exportException.message ?: "Export failed.")
            }
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

    private fun editedMediaItem(spec: RenderSpec, overlay: Bitmap): EditedMediaItem {
        val clipping = MediaItem.ClippingConfiguration.Builder()
            .setStartPositionMs(spec.clipStartMs)
            .setEndPositionMs(spec.clipEndMs)
            .build()
        val mediaItem = MediaItem.Builder()
            .setUri(Uri.fromFile(File(spec.inputPath)))
            .setClippingConfiguration(clipping)
            .build()
        return EditedMediaItem.Builder(mediaItem)
            .setEffects(Effects(listOf(), videoEffects(spec, overlay)))
            .build()
    }

    /** Framing first, the caption and branding overlay always last. */
    private fun videoEffects(spec: RenderSpec, overlay: Bitmap): List<Effect> {
        val fitOutput = Presentation.createForWidthAndHeight(
            spec.outputWidth,
            spec.outputHeight,
            Presentation.LAYOUT_SCALE_TO_FIT,
        )
        val framing = when (val fill = spec.fill) {
            is Fill.Crop -> listOf(Crop(fill.left, fill.right, fill.bottom, fill.top), fitOutput)
            // The blur runs on the source frame: it draws that whole frame sharp at the given
            // scale, and its output already has the output's aspect.
            is Fill.Blur -> listOf(
                GaussianBlurWithFrameOverlaid(fill.sigma, fill.sharpScaleX, fill.sharpScaleY),
                fitOutput,
            )
            Fill.None -> listOf(fitOutput)
        }
        return framing + OverlayEffect(listOf(BitmapOverlay.createStaticBitmapOverlay(overlay)))
    }
}
