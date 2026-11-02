package com.hotmail.arehmananis.statusstudio.youtube

import org.junit.Assert.assertEquals
import org.junit.Test

class YtDlpCommandsTest {
    @Test
    fun video_info_options_dump_one_video_as_json() {
        assertEquals(
            listOf(
                "-J",
                "--no-playlist",
                "--no-warnings",
                "--cache-dir",
                "/cache/yt-dlp",
                "--extractor-args",
                "youtube:skip=hls,dash",
            ),
            videoInfoOptions(cacheDir = "/cache/yt-dlp"),
        )
    }

    @Test
    fun quick_video_info_options_turn_off_javascript() {
        assertEquals(
            "--no-js-runtimes",
            quickVideoInfoOptions(cacheDir = "/cache/yt-dlp").last(),
        )
    }

    @Test
    fun video_url_is_the_watch_page() {
        assertEquals("https://www.youtube.com/watch?v=s6kE_uP3xH4", videoUrl("s6kE_uP3xH4"))
    }
}
