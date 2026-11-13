package com.hotmail.arehmananis.statusstudio.render

/**
 * How much of the outgoing cut shows (its opacity, and its sound's volume) [progress] of the way
 * through a transition (spec FR-37). Fade through black empties the first half to black.
 */
fun outgoingLevel(transition: JoinTransition, progress: Float): Float =
    when (transition) {
        JoinTransition.FADE_THROUGH_BLACK -> (1f - 2f * progress).coerceIn(0f, 1f)
        JoinTransition.CUT -> 1f
        JoinTransition.CROSSFADE, JoinTransition.SLIDE -> 1f - progress
    }

/** The incoming cut's level, the mirror of [outgoingLevel]. */
fun incomingLevel(transition: JoinTransition, progress: Float): Float =
    when (transition) {
        JoinTransition.FADE_THROUGH_BLACK -> (2f * progress - 1f).coerceIn(0f, 1f)
        JoinTransition.CUT -> 0f
        JoinTransition.CROSSFADE, JoinTransition.SLIDE -> progress
    }

/**
 * The volume of an upper-layer item [timeMs] into it: full, then down over its tail as the
 * outgoing cut's level.
 */
fun upperVolumeAt(item: JoinItem, transition: JoinTransition, timeMs: Long): Float {
    val tailStartMs = item.lengthMs - item.blendMs
    if (item.blendMs <= 0 || timeMs < tailStartMs) return 1f
    val progress = ((timeMs - tailStartMs).toFloat() / item.blendMs).coerceIn(0f, 1f)
    return outgoingLevel(transition, progress)
}

/**
 * The volume of a lower-layer item [timeMs] into it: up over its lead as the incoming cut's
 * level, then silent, since from there the upper layer plays the same cut.
 */
fun lowerVolumeAt(item: JoinItem, transition: JoinTransition, timeMs: Long): Float {
    if (item.blendMs <= 0 || timeMs >= item.blendMs) return 0f
    return incomingLevel(transition, timeMs.toFloat() / item.blendMs)
}
