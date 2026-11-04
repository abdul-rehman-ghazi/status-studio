package com.hotmail.arehmananis.statusstudio.render

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class RenderSpecTest {
    private fun specMap(vararg fill: Pair<String, Any?>): Map<String, Any?> =
        mapOf(
            "inputPath" to "/cache/clip.mp4",
            "outputPath" to "/files/reel.mp4",
            "overlayPath" to "/cache/overlay.png",
            "clipStartMs" to 5000,
            "clipEndMs" to 25000,
            "outputWidth" to 1080,
            "outputHeight" to 1920,
            "videoMimeType" to "video/avc",
            "audioMimeType" to "audio/mp4a-latm",
        ) + fill

    @Test
    fun fromMap_parses_crop_spec() {
        val map = specMap(
            "fill" to "crop",
            "crop" to mapOf("left" to -0.3, "right" to 0.3, "bottom" to -1.0, "top" to 1.0),
        )

        val spec = RenderSpec.fromMap(map)

        assertEquals(Fill.Crop(left = -0.3f, right = 0.3f, bottom = -1f, top = 1f), spec.fill)
    }

    @Test
    fun fromMap_parses_blur_spec_without_crop() {
        val map = specMap(
            "fill" to "blur",
            "blurSigma" to 20.0,
            "sharpScaleX" to 1.0,
            "sharpScaleY" to 0.3164,
        )

        val spec = RenderSpec.fromMap(map)

        assertEquals(Fill.Blur(sigma = 20f, sharpScaleX = 1f, sharpScaleY = 0.3164f), spec.fill)
    }

    @Test
    fun fromMap_parses_clip_times_sent_as_ints() {
        val spec = RenderSpec.fromMap(specMap("fill" to "none"))

        assertEquals(5000L to 25000L, spec.clipStartMs to spec.clipEndMs)
    }

    @Test
    fun fromMap_rejects_missing_output_path() {
        val map = specMap("fill" to "none") - "outputPath"

        assertThrows(IllegalArgumentException::class.java) { RenderSpec.fromMap(map) }
    }

    @Test
    fun fromMap_rejects_unknown_fill() {
        val map = specMap("fill" to "sepia")

        assertThrows(IllegalArgumentException::class.java) { RenderSpec.fromMap(map) }
    }

    private val cues = listOf(
        CaptionCue(startMs = 0, endMs = 4000, path = "/cache/overlay_1.png"),
        CaptionCue(startMs = 4000, endMs = 9000, path = "/cache/overlay_2.png"),
    )

    @Test
    fun fromMap_parses_caption_cues() {
        val map = specMap("fill" to "none") + ("captionCues" to listOf(
            mapOf("startMs" to 0, "endMs" to 4000L, "path" to "/cache/overlay_1.png"),
        ))

        val spec = RenderSpec.fromMap(map)

        assertEquals(listOf(cues[0]), spec.captionCues)
    }

    @Test
    fun fromMap_without_cues_has_none() {
        val spec = RenderSpec.fromMap(specMap("fill" to "none"))

        assertEquals(emptyList<CaptionCue>(), spec.captionCues)
    }

    @Test
    fun fromMap_rejects_cue_without_path() {
        val map = specMap("fill" to "none") + ("captionCues" to listOf(
            mapOf("startMs" to 0, "endMs" to 4000),
        ))

        assertThrows(IllegalArgumentException::class.java) { RenderSpec.fromMap(map) }
    }

    @Test
    fun overlayPathAt_gives_the_line_due() {
        assertEquals("/cache/overlay_2.png", overlayPathAt("/cache/overlay.png", cues, 4500))
    }

    @Test
    fun overlayPathAt_ends_a_cue_exclusively() {
        assertEquals("/cache/overlay_2.png", overlayPathAt("/cache/overlay.png", cues, 4000))
    }

    @Test
    fun overlayPathAt_gives_branding_between_and_after_cues() {
        assertEquals("/cache/overlay.png", overlayPathAt("/cache/overlay.png", cues, 9000))
    }
}
