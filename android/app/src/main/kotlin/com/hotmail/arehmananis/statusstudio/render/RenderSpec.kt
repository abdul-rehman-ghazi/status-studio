package com.hotmail.arehmananis.statusstudio.render

/** How the source frame fills the output (spec §6.3.1). */
sealed interface Fill {
    /** A crop in normalised device coordinates, then scaled to the output. */
    data class Crop(val left: Float, val right: Float, val bottom: Float, val top: Float) : Fill

    /** A crop window that moves over the clip (spec §6.3.2), times counted from the clip start. */
    data class MovingCrop(val keyframes: List<CropKeyframe>) : Fill

    /** The whole frame sharp at this share of the output, over a blurred copy. */
    data class Blur(val sigma: Float, val sharpScaleX: Float, val sharpScaleY: Float) : Fill

    /** The source framing as it is (16:9). */
    data object None : Fill
}

/** One caption line's overlay image, shown from [startMs] up to [endMs] of the clip. */
data class CaptionCue(val startMs: Long, val endMs: Long, val path: String)

/**
 * The overlay image for [timeMs] into the clip: the line due then, else the branding on
 * its own (spec FR-7a). The end of a cue is exclusive, so back-to-back lines never overlap.
 */
fun overlayPathAt(brandingPath: String, cues: List<CaptionCue>, timeMs: Long): String =
    cues.firstOrNull { timeMs >= it.startMs && timeMs < it.endMs }?.path ?: brandingPath

/** One export, as sent by Dart's `renderSpecFor`. */
data class RenderSpec(
    val inputPath: String,
    val outputPath: String,
    val overlayPath: String,
    val captionCues: List<CaptionCue>,
    val clipStartMs: Long,
    val clipEndMs: Long,
    val outputWidth: Int,
    val outputHeight: Int,
    val fill: Fill,
    val videoMimeType: String,
    val audioMimeType: String,
) {
    companion object {
        /** Throws [IllegalArgumentException] for a missing or wrong-typed key. */
        fun fromMap(map: Map<String, Any?>): RenderSpec =
            RenderSpec(
                inputPath = map.string("inputPath"),
                outputPath = map.string("outputPath"),
                overlayPath = map.string("overlayPath"),
                captionCues = cuesFrom(map),
                clipStartMs = map.number("clipStartMs").toLong(),
                clipEndMs = map.number("clipEndMs").toLong(),
                outputWidth = map.number("outputWidth").toInt(),
                outputHeight = map.number("outputHeight").toInt(),
                fill = fillFrom(map),
                videoMimeType = map.string("videoMimeType"),
                audioMimeType = map.string("audioMimeType"),
            )

        private fun fillFrom(map: Map<String, Any?>): Fill =
            when (val fill = map.string("fill")) {
                "crop" -> if (map.containsKey("cropKeyframes")) {
                    Fill.MovingCrop(keyframesFrom(map))
                } else {
                    cropFrom(map.submap("crop"))
                }
                "blur" -> Fill.Blur(
                    sigma = map.number("blurSigma").toFloat(),
                    sharpScaleX = map.number("sharpScaleX").toFloat(),
                    sharpScaleY = map.number("sharpScaleY").toFloat(),
                )
                "none" -> Fill.None
                else -> throw IllegalArgumentException("Unknown fill '$fill'.")
            }

        private fun cuesFrom(map: Map<String, Any?>): List<CaptionCue> {
            val cues = map["captionCues"] ?: return emptyList()
            val entries = cues as? List<*>
                ?: throw IllegalArgumentException("'captionCues' must be a list.")
            return entries.map { entry ->
                val cue = (entry as? Map<*, *>)
                    ?.entries
                    ?.associate { (key, value) -> key.toString() to value }
                    ?: throw IllegalArgumentException("A caption cue must be a map.")
                CaptionCue(
                    startMs = cue.number("startMs").toLong(),
                    endMs = cue.number("endMs").toLong(),
                    path = cue.string("path"),
                )
            }
        }

        private fun keyframesFrom(map: Map<String, Any?>): List<CropKeyframe> {
            val entries = map["cropKeyframes"] as? List<*>
                ?: throw IllegalArgumentException("'cropKeyframes' must be a list.")
            require(entries.isNotEmpty()) { "'cropKeyframes' must not be empty." }
            return entries.map { entry ->
                val keyframe = (entry as? Map<*, *>)
                    ?.entries
                    ?.associate { (key, value) -> key.toString() to value }
                    ?: throw IllegalArgumentException("A crop keyframe must be a map.")
                CropKeyframe(
                    timeMs = keyframe.number("timeMs").toLong(),
                    glide = keyframe.string("arrival") == "glide",
                    rect = NdcRect(
                        left = keyframe.number("left").toFloat(),
                        right = keyframe.number("right").toFloat(),
                        bottom = keyframe.number("bottom").toFloat(),
                        top = keyframe.number("top").toFloat(),
                    ),
                )
            }
        }

        private fun cropFrom(crop: Map<String, Any?>): Fill.Crop =
            Fill.Crop(
                left = crop.number("left").toFloat(),
                right = crop.number("right").toFloat(),
                bottom = crop.number("bottom").toFloat(),
                top = crop.number("top").toFloat(),
            )
    }
}

private fun Map<String, Any?>.string(key: String): String =
    this[key] as? String ?: throw IllegalArgumentException("'$key' must be a string.")

// The channel sends Dart ints as Int or Long depending on size, and doubles as Double.
private fun Map<String, Any?>.number(key: String): Number =
    this[key] as? Number ?: throw IllegalArgumentException("'$key' must be a number.")

private fun Map<String, Any?>.submap(key: String): Map<String, Any?> {
    val value = this[key] as? Map<*, *> ?: throw IllegalArgumentException("'$key' must be a map.")
    return value.entries.associate { (entryKey, entryValue) -> entryKey.toString() to entryValue }
}
