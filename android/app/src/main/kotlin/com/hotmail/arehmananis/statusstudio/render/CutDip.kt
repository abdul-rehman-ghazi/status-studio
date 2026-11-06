package com.hotmail.arehmananis.statusstudio.render

import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.RgbMatrix
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos

/** A scene's Cut keyframe sits this long before the cut (Dart's `cutKeyframeLead`, spec FR-27). */
const val CUT_KEYFRAME_LEAD_MS = 10L

/** How far either side of a cut the picture dims. The same numbers as Dart's `cut_dip.dart`. */
private const val DIP_HALF_WIDTH_MS = 160L

/** The dimmest the picture gets, on the cut itself. */
private const val DIP_FLOOR = 0.4f

/** The clip times of the scene cuts: every Cut keyframe after the first, at its cut. */
fun cutTimesMs(keyframes: List<CropKeyframe>): List<Long> =
    keyframes.drop(1).filter { !it.glide }.map { it.timeMs + CUT_KEYFRAME_LEAD_MS }

/**
 * How bright the picture is at [timeMs] (spec FR-22): [DIP_FLOOR] on a cut, easing back to 1 along
 * a cosine over [DIP_HALF_WIDTH_MS] either side, so there is no corner at the cut or at the ends of
 * the dip. 1 away from every cut.
 */
fun cutDipFactorAt(cutTimesMs: List<Long>, timeMs: Long): Float {
    var factor = 1f
    for (cut in cutTimesMs) {
        val away = abs(timeMs - cut)
        if (away >= DIP_HALF_WIDTH_MS) continue
        val eased = ((1 - cos(PI * away / DIP_HALF_WIDTH_MS)) / 2).toFloat()
        factor = minOf(factor, DIP_FLOOR + (1 - DIP_FLOOR) * eased)
    }
    return factor
}

/**
 * Dims the picture to black around each scene cut. After the crop and before the caption
 * overlay, so the captions are never dimmed. The frame's time is read as the crop reads it
 * ([clipTimeMs]), so the dip and the crop jump are on the same frames.
 */
@OptIn(markerClass = [UnstableApi::class])
class CutDip(private val cutTimes: List<Long>) : RgbMatrix {
    override fun getMatrix(presentationTimeUs: Long, useHdr: Boolean): FloatArray {
        val brightness = cutDipFactorAt(cutTimes, clipTimeMs(presentationTimeUs))
        return floatArrayOf(
            brightness, 0f, 0f, 0f,
            0f, brightness, 0f, 0f,
            0f, 0f, brightness, 0f,
            0f, 0f, 0f, 1f,
        )
    }
}
