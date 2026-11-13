package com.hotmail.arehmananis.statusstudio.render

import androidx.annotation.OptIn
import androidx.media3.common.OverlaySettings
import androidx.media3.common.VideoCompositorSettings
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.StaticOverlaySettings

/** Media3 draws the first sequence on top: the upper layer. */
private const val UPPER_INPUT = 0

/**
 * Lays the join's two layers over each other (spec FR-37). Outside a transition the upper layer
 * covers the lower; inside one the upper gives way: it fades for Crossfade and Fade through
 * black (where the lower stays clear until halfway, so black shows), and for Slide both move
 * left by the progress, the lower coming in from the right.
 */
@OptIn(markerClass = [UnstableApi::class])
class TransitionCompositor(
    private val transition: JoinTransition,
    private val windows: List<TransitionWindow>,
) : VideoCompositorSettings {
    private val covering = StaticOverlaySettings.Builder().build()

    override fun getOutputSize(inputSizes: List<Size>): Size = inputSizes.first()

    override fun getOverlaySettings(inputId: Int, presentationTimeUs: Long): OverlaySettings {
        val progress = windows.firstNotNullOfOrNull { it.progressAt(presentationTimeUs / 1000) }
            ?: return covering
        val isUpper = inputId == UPPER_INPUT
        if (transition == JoinTransition.SLIDE) {
            return shiftedLeft(if (isUpper) progress else progress - 1f)
        }
        val level = if (isUpper) outgoingLevel(transition, progress) else lowerOpacity(progress)
        return StaticOverlaySettings.Builder().setAlphaScale(level).build()
    }

    /** Crossfade keeps the lower layer whole under the fading upper one. */
    private fun lowerOpacity(progress: Float): Float =
        if (transition == JoinTransition.CROSSFADE) 1f else incomingLevel(transition, progress)

    /**
     * The frame moved left by [widths] of itself (negative moves it right). Anchors must stay
     * within -1 to 1, so the move is split between the two: the frame's point at `+w` is put on
     * the output's point at `-w`, a move of `2w` half-widths, which is `w` widths.
     */
    private fun shiftedLeft(widths: Float): OverlaySettings =
        StaticOverlaySettings.Builder()
            .setOverlayFrameAnchor(widths, 0f)
            .setBackgroundFrameAnchor(-widths, 0f)
            .build()
}
