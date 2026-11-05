package com.hotmail.arehmananis.statusstudio.videoin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SharedVideoTest {
    @Test
    fun a_send_of_a_video_is_a_video_share() {
        assertTrue(isVideoShare("android.intent.action.SEND", "video/mp4"))
    }

    @Test
    fun a_view_of_a_video_is_a_video_share() {
        assertTrue(isVideoShare("android.intent.action.VIEW", "video/quicktime"))
    }

    @Test
    fun a_send_of_an_image_is_not_a_video_share() {
        assertFalse(isVideoShare("android.intent.action.SEND", "image/jpeg"))
    }

    @Test
    fun the_launcher_intent_is_not_a_video_share() {
        assertFalse(isVideoShare("android.intent.action.MAIN", null))
    }

    @Test
    fun a_send_without_a_type_is_not_a_video_share() {
        assertFalse(isVideoShare("android.intent.action.SEND", null))
    }

    @Test
    fun the_staged_name_keeps_the_display_name_after_a_timestamp() {
        assertEquals("1700_clip.mp4", stagedFileName("clip.mp4", "video/mp4", 1700))
    }

    @Test
    fun the_staged_name_drops_path_separators() {
        assertEquals("1700_evil.mp4", stagedFileName("../../evil.mp4", "video/mp4", 1700))
    }

    @Test
    fun a_missing_display_name_is_replaced_by_one_with_the_mime_extension() {
        assertEquals("1700_video.mp4", stagedFileName(null, "video/mp4", 1700))
    }

    @Test
    fun a_blank_display_name_is_replaced_like_a_missing_one() {
        assertEquals("1700_video.mp4", stagedFileName("  ", "video/mp4", 1700))
    }

    @Test
    fun an_unknown_mime_type_gets_the_generic_video_extension() {
        assertEquals("1700_video.mp4", stagedFileName(null, "video/x-unknown", 1700))
    }

    @Test
    fun an_enospc_error_means_out_of_space() {
        assertTrue(isOutOfSpace("write failed: ENOSPC (No space left on device)"))
    }

    @Test
    fun a_permission_error_does_not_mean_out_of_space() {
        assertFalse(isOutOfSpace("open failed: EACCES (Permission denied)"))
    }

    @Test
    fun a_missing_message_does_not_mean_out_of_space() {
        assertFalse(isOutOfSpace(null))
    }
}
