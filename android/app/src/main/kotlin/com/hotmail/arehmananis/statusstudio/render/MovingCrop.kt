package com.hotmail.arehmananis.statusstudio.render

import androidx.annotation.OptIn
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.GlMatrixTransformation

private const val MICROS_PER_MILLI = 1000L

/**
 * Milliseconds into the clip for a frame's presentation time. Trimming starts the clip at zero, so
 * the crop and the caption lines read the same clock and can't drift apart.
 */
fun clipTimeMs(presentationTimeUs: Long): Long = presentationTimeUs / MICROS_PER_MILLI

/** A crop rectangle in normalised device coordinates (spec §6.3.1). */
data class NdcRect(val left: Float, val right: Float, val bottom: Float, val top: Float)

/** The crop at [timeMs] into the clip. [glide] is how this keyframe is reached from the one before. */
data class CropKeyframe(val timeMs: Long, val glide: Boolean, val rect: NdcRect)

/**
 * The crop at [timeMs] (spec §6.3.2), the same rule as Dart's `CropPath.anchorAt`: before the first
 * keyframe the first rectangle, after the last the last. Between two, a glide moves each edge in a
 * straight line and a cut holds the earlier rectangle until the later keyframe's time, and from
 * that time on is the later one.
 */
fun ndcRectAt(keyframes: List<CropKeyframe>, timeMs: Long): NdcRect {
    require(keyframes.isNotEmpty()) { "A moving crop needs at least one keyframe." }
    val next = keyframes.indexOfFirst { it.timeMs > timeMs }
    if (next < 0) return keyframes.last().rect
    if (next == 0) return keyframes.first().rect
    val from = keyframes[next - 1]
    val to = keyframes[next]
    if (!to.glide) return from.rect
    val done = (timeMs - from.timeMs).toFloat() / (to.timeMs - from.timeMs)
    return NdcRect(
        left = lerp(from.rect.left, to.rect.left, done),
        right = lerp(from.rect.right, to.rect.right, done),
        bottom = lerp(from.rect.bottom, to.rect.bottom, done),
        top = lerp(from.rect.top, to.rect.top, done),
    )
}

private fun lerp(from: Float, to: Float, fraction: Float): Float = from + (to - from) * fraction

/**
 * Scales [rect] up to fill the frame: the column-major 4 × 4 matrix that maps the rectangle's
 * centre to the frame's centre. Built by hand because unit tests can't use `android.graphics.Matrix`.
 */
fun glMatrixFor(rect: NdcRect): FloatArray {
    val scaleX = 2f / (rect.right - rect.left)
    val scaleY = 2f / (rect.top - rect.bottom)
    val centreX = (rect.right + rect.left) / 2f
    val centreY = (rect.top + rect.bottom) / 2f
    return floatArrayOf(
        scaleX, 0f, 0f, 0f,
        0f, scaleY, 0f, 0f,
        0f, 0f, 1f, 0f,
        -centreX * scaleX, -centreY * scaleY, 0f, 1f,
    )
}

/**
 * A crop whose window moves over the clip (spec §6.3.2). The window keeps one size, so the output
 * size comes from the first keyframe, as Media3's own `Crop` does.
 */
@OptIn(markerClass = [UnstableApi::class])
class MovingCrop(private val keyframes: List<CropKeyframe>) : GlMatrixTransformation {
    init {
        require(keyframes.isNotEmpty()) { "A moving crop needs at least one keyframe." }
    }

    override fun configure(inputWidth: Int, inputHeight: Int): Size {
        val first = keyframes.first().rect
        return Size(
            Math.round(inputWidth * (first.right - first.left) / 2f),
            Math.round(inputHeight * (first.top - first.bottom) / 2f),
        )
    }

    override fun getGlMatrixArray(presentationTimeUs: Long): FloatArray =
        glMatrixFor(ndcRectAt(keyframes, clipTimeMs(presentationTimeUs)))
}
