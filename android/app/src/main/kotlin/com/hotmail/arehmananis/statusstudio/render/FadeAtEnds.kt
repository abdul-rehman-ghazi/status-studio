package com.hotmail.arehmananis.statusstudio.render

import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.RgbMatrix

/**
 * The picture's brightness [clipTimeMs] into a clip [clipLengthMs] long: 0 at both ends, rising
 * and falling in a straight line over [fadeMs], 1 in between. The same rule as Dart's
 * `fadeBrightnessAt` (spec FR-33).
 */
fun fadeBrightnessAt(clipTimeMs: Long, clipLengthMs: Long, fadeMs: Long): Float {
    if (fadeMs <= 0) return 1f
    val fromStart = clipTimeMs.toFloat() / fadeMs
    val toEnd = (clipLengthMs - clipTimeMs).toFloat() / fadeMs
    return minOf(1f, fromStart, toEnd).coerceIn(0f, 1f)
}

/**
 * Fades the picture in from black and out to black (spec FR-33). It runs after the overlay, so
 * the caption and branding fade with the picture.
 */
@OptIn(markerClass = [UnstableApi::class])
class FadeAtEnds(private val clipLengthMs: Long, private val fadeMs: Long) : RgbMatrix {
    override fun getMatrix(presentationTimeUs: Long, useHdr: Boolean): FloatArray {
        val brightness = fadeBrightnessAt(clipTimeMs(presentationTimeUs), clipLengthMs, fadeMs)
        // Column-major 4x4: red, green and blue scaled, alpha kept.
        return floatArrayOf(
            brightness, 0f, 0f, 0f,
            0f, brightness, 0f, 0f,
            0f, 0f, brightness, 0f,
            0f, 0f, 0f, 1f,
        )
    }
}
