package com.hotmail.arehmananis.statusstudio.render

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.FrameDropEffect
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import java.io.File

private const val PROGRESS_INTERVAL_MS = 250L

private const val LOG_TAG = "ClipJoiner"

/** How deep [describe] follows an error's causes. */
private const val MAX_CAUSES = 4

/** Bits a pixel a second: about 10 Mbit/s at 1080p, so the extra encode loses little. */
private const val BITS_PER_PIXEL = 5

/** When the cut file can't be measured: 1080p's rate. */
private const val FALLBACK_BITRATE = 10_000_000

/**
 * The joined clip's frame rate. YouTube's 1080p H.264 is often 60 fps, and the Redmi Note 11
 * refused a 1080p60 encoder beside a 1080p60 decoder with NO_MEMORY (M46 task 13); 30 fps halves
 * the encoder's load here and the decoder's in the reel's export later.
 */
private const val JOIN_FRAME_RATE = 30

/** MediaCodec's priority for real-time work, as opposed to as fast as possible. */
private const val REALTIME_PRIORITY = 0

/**
 * Joins a linked video's cuts into one H.264/AAC file (spec FR-37). Each cut is clipped from its
 * own file at exact times. With a blend, two layers play at once (see [TransitionCompositor]):
 * the upper plays each cut with its tail, without gaps; the lower only each cut's lead, at its
 * window, with gaps between, so a second decoder runs only around the joins. Decoding is in
 * software first (see [softwareFirstAssetLoaderFactory]). Their sound is mixed, each
 * item's volume following [upperVolumeAt] or [lowerVolumeAt]. An AV1 cut is decoded as
 * [VideoConverter] decodes it. One join at a time; must be used from the main thread.
 */
@OptIn(markerClass = [UnstableApi::class])
class ClipJoiner(private val context: Context) {
    interface Listener {
        fun onProgress(fraction: Double)

        fun onDone()

        fun onError(message: String)
    }

    private class Running(
        val transformer: Transformer,
        val outputPath: String,
        val poll: Runnable,
        val listener: Listener,
    )

    private val mainHandler = Handler(Looper.getMainLooper())
    private var running: Running? = null

    val isBusy: Boolean
        get() = running != null

    /** Throws any exception Media3 raises for a spec it rejects at once. */
    fun join(spec: JoinSpec, listener: Listener) {
        check(running == null) { "A join is already running." }
        val transformer = Transformer.Builder(context)
            .setAssetLoaderFactory(softwareFirstAssetLoaderFactory(context))
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .setEncoderFactory(encoderFactory(bitrateFor(spec.upper.first().path)))
            .addListener(completionListener(listener))
            .build()
        transformer.start(composition(spec), spec.outputPath)
        val poll = progressPoll(transformer, listener)
        running = Running(transformer, spec.outputPath, poll, listener)
        mainHandler.post(poll)
    }

    /**
     * Stops the join and deletes the partial file. Media3 says nothing after a cancel, so the
     * listener hears it as an error here, and the channel call waiting on it ends.
     */
    fun cancel() {
        val current = finish() ?: return
        try {
            current.transformer.cancel()
        } finally {
            File(current.outputPath).delete()
            current.listener.onError("Cancelled.")
        }
    }

    private fun composition(spec: JoinSpec): Composition {
        val upper = EditedMediaItemSequence.Builder(
            spec.upper.map { item ->
                editedItem(item) { timeMs -> upperVolumeAt(item, spec.transition, timeMs) }
            },
        ).build()
        if (spec.lower.isEmpty()) return Composition.Builder(upper).setEffects(atJoinFrameRate()).build()
        return Composition.Builder(upper, lowerSequence(spec))
            .setVideoCompositorSettings(TransitionCompositor(spec.transition, spec.windows))
            .setEffects(atJoinFrameRate())
            .build()
    }

    /**
     * Each cut's lead, placed at its transition's window, with gaps between and after: the lower
     * layer decodes only around the joins. A gap is black and silent, and the upper layer covers
     * it. It starts with a gap, so its tracks are named up front.
     */
    private fun lowerSequence(spec: JoinSpec): EditedMediaItemSequence {
        // Naming the tracks is what lets a sequence start with a gap. The older force-track
        // setters must not be called as well: Media3 refuses them on a builder made this way.
        val lower = EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_AUDIO, C.TRACK_TYPE_VIDEO))
        var placedMs = 0L
        spec.lower.zip(spec.windows).forEach { (item, window) ->
            addGap(lower, window.startMs - placedMs)
            val lead = editedItem(item) { timeMs -> lowerVolumeAt(item, spec.transition, timeMs) }
            lower.addItem(lead)
            placedMs = window.startMs + item.lengthMs
        }
        addGap(lower, spec.lengthMs - placedMs)
        return lower.build()
    }

    private fun addGap(sequence: EditedMediaItemSequence.Builder, lengthMs: Long) {
        if (lengthMs > 0) sequence.addGap(lengthMs * 1000)
    }

    private fun editedItem(item: JoinItem, volumeAtMs: (Long) -> Float): EditedMediaItem {
        val clipping = MediaItem.ClippingConfiguration.Builder()
            .setStartPositionMs(item.startMs)
            .setEndPositionMs(item.endMs)
            .build()
        val mediaItem = MediaItem.Builder()
            .setUri(Uri.fromFile(File(item.path)))
            .setClippingConfiguration(clipping)
            .build()
        return EditedMediaItem.Builder(mediaItem)
            .setEffects(Effects(listOf(VolumeEnvelope(volumeAtMs)), listOf()))
            .build()
    }

    /**
     * Media3 asks for the encoder's top speed by default (operating rate `Int.MAX_VALUE`), which
     * reserves the chip's whole budget; asking for real time at 30 fps leaves room for the
     * decoders.
     */
    private fun encoderFactory(bitrate: Int): DefaultEncoderFactory {
        val settings = VideoEncoderSettings.Builder()
            .setBitrate(bitrate)
            .setEncoderPerformanceParameters(JOIN_FRAME_RATE, REALTIME_PRIORITY)
            .build()
        return DefaultEncoderFactory.Builder(context)
            .setRequestedVideoEncoderSettings(settings)
            .build()
    }

    /** Applied to the composed picture, so both layers are already blended. */
    private fun atJoinFrameRate(): Effects =
        Effects(listOf(), listOf(FrameDropEffect.createDefaultFrameDropEffect(JOIN_FRAME_RATE.toFloat())))

    /** All cuts come from one stream, so the first file's size stands for all. */
    private fun bitrateFor(path: String): Int {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
            if (width == null || height == null) FALLBACK_BITRATE else width * height * BITS_PER_PIXEL
        } catch (error: RuntimeException) {
            FALLBACK_BITRATE
        } finally {
            retriever.release()
        }
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
                finish() ?: return
                listener.onDone()
            }

            override fun onError(
                composition: Composition,
                exportResult: ExportResult,
                exportException: ExportException,
            ) {
                val failed = finish() ?: return
                File(failed.outputPath).delete()
                Log.e(LOG_TAG, "Join failed", exportException)
                listener.onError(describe(exportException))
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
}

/**
 * Media3's error code, message and causes on one line, so the failure shown on Review cuts says
 * which of Media3's checks stopped the join (spec §8: the detail under "Couldn't join the cuts").
 */
@OptIn(markerClass = [UnstableApi::class])
fun describe(exportException: ExportException): String {
    val causes = generateSequence(exportException.cause) { it.cause }
        .take(MAX_CAUSES)
        .map { "${it.javaClass.simpleName}: ${it.message}" }
        .toList()
    return (listOf("${exportException.errorCodeName}: ${exportException.message}") + causes)
        .joinToString(" <- ")
}

/**
 * [error]'s class, message and the line that threw it: Media3's own checks throw with no message,
 * so the line is what tells them apart.
 */
fun describe(error: RuntimeException): String {
    val thrownAt = error.stackTrace.firstOrNull()?.let { " at ${it.className}.${it.methodName}:${it.lineNumber}" } ?: ""
    return "${error.javaClass.simpleName}: ${error.message}$thrownAt"
}
