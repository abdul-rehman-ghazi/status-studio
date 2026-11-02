package com.hotmail.arehmananis.statusstudio.render

/** How the source frame fills the output (spec §6.3.1). */
sealed interface Fill {
    /** A crop in normalised device coordinates, then scaled to the output. */
    data class Crop(val left: Float, val right: Float, val bottom: Float, val top: Float) : Fill

    /** The whole frame sharp at this share of the output, over a blurred copy. */
    data class Blur(val sigma: Float, val sharpScaleX: Float, val sharpScaleY: Float) : Fill

    /** The source framing as it is (16:9). */
    data object None : Fill
}

/** One export, as sent by Dart's `renderSpecFor`. */
data class RenderSpec(
    val inputPath: String,
    val outputPath: String,
    val overlayPath: String,
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
                "crop" -> cropFrom(map.submap("crop"))
                "blur" -> Fill.Blur(
                    sigma = map.number("blurSigma").toFloat(),
                    sharpScaleX = map.number("sharpScaleX").toFloat(),
                    sharpScaleY = map.number("sharpScaleY").toFloat(),
                )
                "none" -> Fill.None
                else -> throw IllegalArgumentException("Unknown fill '$fill'.")
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
