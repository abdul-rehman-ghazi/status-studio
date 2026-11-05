package com.hotmail.arehmananis.statusstudio.videoin

import java.io.File
import java.io.IOException
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SharedVideoTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

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
    fun the_staged_name_keeps_the_display_name_after_the_prefix() {
        assertEquals("1700-1_clip.mp4", stagedFileName("clip.mp4", "video/mp4", "1700-1"))
    }

    @Test
    fun the_staged_name_drops_path_separators() {
        assertEquals("p_evil.mp4", stagedFileName("../../evil.mp4", "video/mp4", "p"))
    }

    @Test
    fun the_staged_name_drops_windows_separators() {
        assertEquals("p_evil.mp4", stagedFileName("..\\..\\evil.mp4", "video/mp4", "p"))
    }

    @Test
    fun a_name_of_only_dots_is_replaced_by_the_fallback() {
        assertEquals("p_video.mp4", stagedFileName("..", "video/mp4", "p"))
    }

    @Test
    fun a_missing_display_name_is_replaced_by_one_with_the_mime_extension() {
        assertEquals("p_video.mov", stagedFileName(null, "video/quicktime", "p"))
    }

    @Test
    fun a_blank_display_name_is_replaced_like_a_missing_one() {
        assertEquals("p_video.mp4", stagedFileName("  ", "video/mp4", "p"))
    }

    @Test
    fun an_unknown_mime_type_gets_the_generic_video_extension() {
        assertEquals("p_video.mp4", stagedFileName(null, "video/x-unknown", "p"))
    }

    @Test
    fun a_name_without_an_extension_gets_one_from_the_mime_type() {
        assertEquals("p_holiday.webm", stagedFileName("holiday", "video/webm", "p"))
    }

    @Test
    fun a_name_with_a_dot_but_no_video_extension_gets_one_added() {
        assertEquals("p_my.video.clip.mp4", stagedFileName("my.video.clip", "video/mp4", "p"))
    }

    @Test
    fun an_urdu_name_is_kept_whole() {
        assertEquals("p_محفل.mp4", stagedFileName("محفل.mp4", "video/mp4", "p"))
    }

    @Test
    fun a_300_character_name_fits_in_255_bytes_and_keeps_its_extension() {
        val name = stagedFileName("a".repeat(300) + ".mp4", "video/mp4", "1700-1")

        assertEquals(255, name.toByteArray().size)
        assertTrue(name.endsWith(".mp4"))
    }

    @Test
    fun a_long_urdu_name_is_cut_between_characters() {
        val name = stagedFileName("ک".repeat(200) + ".mp4", "video/mp4", "1700-1")

        assertTrue(name.toByteArray().size <= 255)
        assertEquals(name, String(name.toByteArray(), Charsets.UTF_8))
        assertFalse(name.contains('\uFFFD'))
        assertTrue(name.endsWith(".mp4"))
    }

    @Test
    fun a_name_with_characters_outside_the_basic_plane_is_not_split() {
        val name = stagedFileName("\uD83C\uDFAC".repeat(100) + ".mp4", "video/mp4", "1700-1")

        assertTrue(name.toByteArray().size <= 255)
        assertEquals(0, name.count { it == '\uFFFD' })
        assertTrue(name.removeSuffix(".mp4").removePrefix("1700-1_").all { it == '\uD83C' || it == '\uDFAC' })
    }

    @Test
    fun two_shares_with_the_same_name_get_different_staged_names() {
        val first = stagedFileName("clip.mp4", "video/mp4", "1700-1")
        val second = stagedFileName("clip.mp4", "video/mp4", "1700-2")

        assertNotEquals(first, second)
    }

    @Test
    fun a_launch_from_recents_is_not_handled() {
        assertFalse(shouldHandleIntent(0x00100000, restoredBySystem = false))
    }

    @Test
    fun a_restored_activity_does_not_handle_its_old_intent() {
        assertFalse(shouldHandleIntent(0, restoredBySystem = true))
    }

    @Test
    fun a_fresh_launch_is_handled() {
        assertTrue(shouldHandleIntent(0x10000000, restoredBySystem = false))
    }

    @Test
    fun a_video_that_leaves_the_margin_free_fits() {
        assertTrue(hasRoomFor(100L, 100L + 50L * 1024 * 1024))
    }

    @Test
    fun a_video_that_eats_into_the_margin_does_not_fit() {
        assertFalse(hasRoomFor(100L, 100L + 50L * 1024 * 1024 - 1))
    }

    @Test
    fun a_video_of_unknown_size_is_tried() {
        assertTrue(hasRoomFor(null, 0L))
    }

    @Test
    fun running_out_of_space_while_copying_reports_no_space() {
        assertEquals("no_space", failureCodeOf(IOException("write failed: ENOSPC (No space left on device)")))
    }

    @Test
    fun too_little_free_space_before_copying_reports_no_space() {
        assertEquals("no_space", failureCodeOf(InsufficientStorageException("full")))
    }

    @Test
    fun a_runtime_failure_reports_copy_failed() {
        assertEquals("copy_failed", failureCodeOf(IllegalStateException("cursor closed")))
    }

    @Test
    fun a_file_inside_the_folder_is_inside_it() {
        val folder = temporaryFolder.newFolder("data")

        assertTrue(isInsideDirectory(File(folder, "databases/app.db"), folder))
    }

    @Test
    fun a_dotdot_path_that_leaves_the_folder_is_outside_it() {
        val folder = temporaryFolder.newFolder("data")

        assertFalse(isInsideDirectory(File(folder, "../elsewhere/clip.mp4"), folder))
    }

    @Test
    fun a_sibling_folder_with_the_same_prefix_is_outside_it() {
        val folder = temporaryFolder.newFolder("data")
        val sibling = temporaryFolder.newFolder("data-other")

        assertFalse(isInsideDirectory(File(sibling, "clip.mp4"), folder))
    }

    @Test
    fun a_symbolic_link_into_the_folder_is_inside_it() {
        val folder = temporaryFolder.newFolder("data")
        val link = File(temporaryFolder.root, "link")
        Files.createSymbolicLink(link.toPath(), folder.toPath())

        assertTrue(isInsideDirectory(File(link, "secret"), folder))
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
