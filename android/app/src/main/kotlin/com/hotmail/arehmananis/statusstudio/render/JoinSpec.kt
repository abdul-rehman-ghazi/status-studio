package com.hotmail.arehmananis.statusstudio.render

/** How one cut gives way to the next (spec FR-37); the names are Dart's `ClipTransition`. */
enum class JoinTransition {
    CUT,
    CROSSFADE,
    FADE_THROUGH_BLACK,
    SLIDE;

    companion object {
        fun fromName(name: String): JoinTransition =
            when (name) {
                "cut" -> CUT
                "crossfade" -> CROSSFADE
                "fadeThroughBlack" -> FADE_THROUGH_BLACK
                "slide" -> SLIDE
                else -> throw IllegalArgumentException("Unknown transition $name.")
            }
    }
}

/**
 * One stretch of a cut file in a layer, in the file's own time. The upper layer's items blend
 * out over their last [blendMs]; the lower layer's blend in over their first [blendMs].
 */
data class JoinItem(val path: String, val startMs: Long, val endMs: Long, val blendMs: Long) {
    val lengthMs: Long
        get() = endMs - startMs
}

/** When a transition plays, in the joined clip's time. */
data class TransitionWindow(val startMs: Long, val endMs: Long) {
    /** How far into the window [timeMs] is, 0 to 1; null outside it. */
    fun progressAt(timeMs: Long): Float? {
        if (timeMs < startMs || timeMs >= endMs) return null
        return (timeMs - startMs).toFloat() / (endMs - startMs)
    }
}

/** One join, as sent by Dart's `JoinPlan.toChannel` (spec FR-37). */
data class JoinSpec(
    val outputPath: String,
    val transition: JoinTransition,
    val upper: List<JoinItem>,
    val lower: List<JoinItem>,
    val windows: List<TransitionWindow>,
) {
    companion object {
        /** Throws [IllegalArgumentException] for a missing or wrong-typed key. */
        fun fromMap(map: Map<String, Any?>): JoinSpec {
            val upper = map.maps("upper").map(::itemFrom)
            require(upper.isNotEmpty()) { "A join needs at least one cut." }
            return JoinSpec(
                outputPath = map.text("outputPath"),
                transition = JoinTransition.fromName(map.text("transition")),
                upper = upper,
                lower = map.maps("lower").map(::itemFrom),
                windows = map.maps("windows").map {
                    TransitionWindow(it.whole("startMs"), it.whole("endMs"))
                },
            )
        }

        private fun itemFrom(map: Map<String, Any?>): JoinItem =
            JoinItem(
                path = map.text("path"),
                startMs = map.whole("startMs"),
                endMs = map.whole("endMs"),
                blendMs = map.whole("blendMs"),
            )
    }
}

private fun Map<String, Any?>.text(key: String): String =
    this[key] as? String ?: throw IllegalArgumentException("$key must be a string.")

private fun Map<String, Any?>.whole(key: String): Long =
    (this[key] as? Number)?.toLong() ?: throw IllegalArgumentException("$key must be a number.")

private fun Map<String, Any?>.maps(key: String): List<Map<String, Any?>> {
    val list = this[key] as? List<*> ?: throw IllegalArgumentException("$key must be a list.")
    return list.map { entry ->
        val map = entry as? Map<*, *> ?: throw IllegalArgumentException("$key holds a non-map.")
        map.entries.associate { it.key.toString() to it.value }
    }
}
