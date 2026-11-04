package com.hotmail.arehmananis.statusstudio.render

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

/** The same cases as Dart's `crop_path_test.dart`: the two sides must agree at every boundary. */
class MovingCropTest {
    private val left = NdcRect(-1f, -0.4f, -1f, 1f)
    private val right = NdcRect(0.4f, 1f, -1f, 1f)

    private fun leftThenRightAtTenSeconds(glide: Boolean) = listOf(
        CropKeyframe(0, true, left),
        CropKeyframe(10_000, glide, right),
    )

    @Test
    fun before_the_first_keyframe_it_is_the_first_rectangle() {
        assertEquals(left, ndcRectAt(leftThenRightAtTenSeconds(true), -500))
    }

    @Test
    fun after_the_last_keyframe_it_holds_the_last_rectangle() {
        assertEquals(right, ndcRectAt(leftThenRightAtTenSeconds(true), 20_000))
    }

    @Test
    fun a_glide_a_quarter_of_the_way_moves_a_quarter() {
        val rect = ndcRectAt(leftThenRightAtTenSeconds(true), 2_500)

        assertEquals(-0.65f, rect.left, 1e-5f)
    }

    @Test
    fun a_glide_arrives_at_its_keyframe_time() {
        assertEquals(right, ndcRectAt(leftThenRightAtTenSeconds(true), 10_000))
    }

    @Test
    fun a_cut_holds_the_earlier_rectangle_just_before_its_time() {
        assertEquals(left, ndcRectAt(leftThenRightAtTenSeconds(false), 9_999))
    }

    @Test
    fun a_cut_has_jumped_at_exactly_its_time() {
        assertEquals(right, ndcRectAt(leftThenRightAtTenSeconds(false), 10_000))
    }

    @Test
    fun the_matrix_of_the_whole_frame_is_the_identity() {
        val matrix = glMatrixFor(NdcRect(-1f, 1f, -1f, 1f))

        assertArrayEquals(
            floatArrayOf(1f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 1f),
            matrix,
            0f,
        )
    }

    @Test
    fun the_matrix_scales_by_the_inverse_of_the_window_size() {
        val matrix = glMatrixFor(NdcRect(-1f, 0f, -1f, 1f))

        assertEquals(2f, matrix[0], 0f)
    }

    @Test
    fun the_matrix_moves_the_window_centre_to_the_frame_centre() {
        val matrix = glMatrixFor(NdcRect(0f, 1f, -1f, 1f))

        // x' = x * scaleX + translateX, so the window's centre x = 0.5 lands on 0.
        assertEquals(0f, 0.5f * matrix[0] + matrix[12], 1e-6f)
    }

    @Test
    fun the_clip_clock_is_the_presentation_time_in_milliseconds() {
        assertEquals(1_500L, clipTimeMs(1_500_000L))
    }
}
