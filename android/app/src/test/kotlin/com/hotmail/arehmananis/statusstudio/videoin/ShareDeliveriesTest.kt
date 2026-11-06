package com.hotmail.arehmananis.statusstudio.videoin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ShareDeliveriesTest {
    private val pushed = mutableListOf<Pair<String, Map<String, Any?>>>()
    private val deliveries = ShareDeliveries { method, arguments -> pushed.add(method to arguments) }

    @Test
    fun a_share_before_dart_listens_is_kept_for_its_first_listen() {
        deliveries.deliver("incomingVideo", mapOf("path" to "/a"))

        val kept = deliveries.startListening()

        assertEquals(
            listOf(mapOf("method" to "incomingVideo", "arguments" to mapOf("path" to "/a"))),
            kept,
        )
    }

    @Test
    fun a_kept_share_is_handed_over_only_once() {
        deliveries.deliver("incomingVideo", mapOf("path" to "/a"))
        deliveries.startListening()

        assertTrue(deliveries.startListening().isEmpty())
    }

    @Test
    fun a_share_while_dart_listens_is_pushed_at_once() {
        deliveries.startListening()

        deliveries.deliver("incomingVideo", mapOf("path" to "/b"))

        assertEquals(listOf("incomingVideo" to mapOf<String, Any?>("path" to "/b")), pushed)
    }

    @Test
    fun a_share_while_dart_listens_is_not_also_kept() {
        deliveries.startListening()
        deliveries.deliver("incomingVideo", mapOf("path" to "/b"))

        assertTrue(deliveries.startListening().isEmpty())
    }

    @Test
    fun a_share_after_stop_listening_is_kept_not_pushed() {
        deliveries.startListening()
        deliveries.stopListening()

        deliveries.deliver("incomingVideo", mapOf("path" to "/c"))

        assertTrue(pushed.isEmpty())
    }

    @Test
    fun a_share_after_stop_listening_reaches_the_next_listen() {
        deliveries.startListening()
        deliveries.stopListening()
        deliveries.deliver("incomingVideoFailed", mapOf("code" to "no_space"))

        val kept = deliveries.startListening()

        assertEquals("incomingVideoFailed", kept.single()["method"])
    }
}
