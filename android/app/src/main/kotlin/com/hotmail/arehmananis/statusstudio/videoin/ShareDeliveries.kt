package com.hotmail.arehmananis.statusstudio.videoin

/**
 * Hands each finished share to Dart: pushed at once while Dart listens, kept otherwise.
 * Dart collects what was kept when it starts listening again. Main thread only.
 */
class ShareDeliveries(private val push: (method: String, arguments: Map<String, Any?>) -> Unit) {
    private val waiting = mutableListOf<Map<String, Any?>>()
    private var dartListening = false

    fun deliver(method: String, arguments: Map<String, Any?>) {
        if (dartListening) {
            push(method, arguments)
            return
        }
        waiting.add(mapOf("method" to method, "arguments" to arguments))
    }

    fun startListening(): List<Map<String, Any?>> {
        dartListening = true
        val kept = waiting.toList()
        waiting.clear()
        return kept
    }

    fun stopListening() {
        dartListening = false
    }
}
