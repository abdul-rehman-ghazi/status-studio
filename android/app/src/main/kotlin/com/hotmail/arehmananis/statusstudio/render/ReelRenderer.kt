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
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.Crop
import androidx.media3.effect.GaussianBlurWithFrameOverlaid
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import java.io.File

private const val PROGRESS_INTERVAL_MS = 250L
private const val REEL_VIDEO_BITRATE = 4_000_000

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

    /**
     * Throws [IllegalArgumentException] when the overlay can't be read, or any exception
     * Media3 raises for a spec it rejects; the renderer stays free either way.
     */
    fun start(spec: RenderSpec, listener: Listener) {
        check(running == null) { "A render is already running." }
        val overlay = TimedCaptionOverlay(spec.overlayPath, spec.captionCues)
        val transformer = Transformer.Builder(context)
            .setVideoMimeType(spec.videoMimeType)
            .setAudioMimeType(spec.audioMimeType)
            .setEncoderFactory(reelEncoderFactory())
            .addListener(completionListener(listener))
            .build()
        // Busy only once `start` has succeeded: a spec Media3 rejects must not
        // leave the renderer refusing every later render.
        transformer.start(editedMediaItem(spec, overlay), spec.outputPath)
        val poll = progressPoll(transformer, listener)
        running = Running(transformer, spec.outputPath, poll)
        mainHandler.post(poll)
    }

    /** Stops the render and deletes the partial file (FR-9). */
    fun cancel() {
        val current = finish() ?: return
        try {
            current.transformer.cancel()
        } finally {
            File(current.outputPath).delete()
        }
    }

    private fun finish(): Running? {
        val current = running ?: return null
        mainHandler.removeCallbacks(current.poll)
        running = null
        return current
    }

    /** Left to itself the hardware encoder chose 8–9 Mbit/s, about 65 MB a minute (FR-48). */
    private fun reelEncoderFactory(): DefaultEncoderFactory {
        val settings = VideoEncoderSettings.Builder()
            .setBitrate(REEL_VIDEO_BITRATE)
            .build()
        return DefaultEncoderFactory.Builder(context)
            .setRequestedVideoEncoderSettings(settings)
            .build()
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

    private fun editedMediaItem(spec: RenderSpec, overlay: TimedCaptionOverlay): EditedMediaItem {
        val clipping = MediaItem.ClippingConfiguration.Builder()
            .setStartPositionMs(spec.clipStartMs)
            .setEndPositionMs(spec.clipEndMs)
            .build()
        val mediaItem = MediaItem.Builder()
            .setUri(Uri.fromFile(File(spec.inputPath)))
            .setClippingConfiguration(clipping)
            .build()
        return EditedMediaItem.Builder(mediaItem)
            .setEffects(Effects(audioEffects(spec), videoEffects(spec, overlay)))
            .build()
    }

    private fun audioEffects(spec: RenderSpec): List<AudioProcessor> =
        if (spec.soundGain > 1f) listOf(LoudnessBoost(spec.soundGain)) else listOf()

    /** Framing first, then the caption and branding overlay, then the fade, if any (FR-33). */
    private fun videoEffects(spec: RenderSpec, overlay: TimedCaptionOverlay): List<Effect> {
        val fitOutput = Presentation.createForWidthAndHeight(
            spec.outputWidth,
            spec.outputHeight,
            Presentation.LAYOUT_SCALE_TO_FIT,
        )
        val framing = when (val fill = spec.fill) {
            // Crop sizes are rounded down to even pixels, so their aspect is a hair off the
            // output's; stretching (under 0.5 %) avoids thin black bars at the edges.
            is Fill.Crop -> listOf(
                Crop(fill.left, fill.right, fill.bottom, fill.top),
                Presentation.createForWidthAndHeight(
                    spec.outputWidth,
                    spec.outputHeight,
                    Presentation.LAYOUT_STRETCH_TO_FIT,
                ),
            )
            // The window moves, but keeps one size, so the same near-1:1 stretch applies.
            is Fill.MovingCrop -> listOf(
                MovingCrop(fill.keyframes),
                Presentation.createForWidthAndHeight(
                    spec.outputWidth,
                    spec.outputHeight,
                    Presentation.LAYOUT_STRETCH_TO_FIT,
                ),
            )
            // The blur runs on the source frame: it draws that whole frame sharp at the given
            // scale, and its output already has the output's aspect.
            is Fill.Blur -> listOf(
                GaussianBlurWithFrameOverlaid(fill.sigma, fill.sharpScaleX, fill.sharpScaleY),
                fitOutput,
            )
            Fill.None -> listOf(fitOutput)
        }
        val overlaid = framing + OverlayEffect(listOf(overlay))
        if (spec.fadeMs <= 0) return overlaid
        return overlaid + FadeAtEnds(spec.clipEndMs - spec.clipStartMs, spec.fadeMs)
    }
}

/**
 * Lays the branding image over the clip, swapping it for the caption line's image while that
 * line is due (spec FR-7a). Images are opened one at a time as they come due: a reel can have
 * dozens, and each is a full-size frame.
 */
@OptIn(markerClass = [UnstableApi::class])
private class TimedCaptionOverlay(
    private val brandingPath: String,
    private val cues: List<CaptionCue>,
) : BitmapOverlay() {
    private var shownPath: String? = null
    private var shown: Bitmap? = null

    init {
        // Fails the render at once, rather than midway, when the branding image is unreadable.
        bitmapAt(brandingPath)
    }

    override fun getBitmap(presentationTimeUs: Long): Bitmap =
        bitmapAt(overlayPathAt(brandingPath, cues, clipTimeMs(presentationTimeUs)))

    private fun bitmapAt(path: String): Bitmap {
        val current = shown
        if (current != null && path == shownPath) {
            return current
        }
        val decoded = BitmapFactory.decodeFile(path)
            ?: throw IllegalArgumentException("Couldn't read the overlay $path.")
        shownPath = path
        shown = decoded
        return decoded
    }
}
