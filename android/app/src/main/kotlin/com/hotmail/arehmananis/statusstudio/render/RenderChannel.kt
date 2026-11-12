package com.hotmail.arehmananis.statusstudio.render

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `status_studio/render` (`start`, `cancel`, and `convert` and `join`, which answer when the file
 * is written, and `cancelJoin`) and `status_studio/render/events`, which sends
 * `{type: progress, value}`, `{type: done, path}` and `{type: error, message}`. A conversion's
 * or a join's progress goes to `status_studio/render/conversion` as `{outputPath, value}`, apart
 * from renders.
 */
class RenderChannel(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private val renderer = ReelRenderer(context)
    private val converter = VideoConverter(context)
    private val joiner = ClipJoiner(context)
    private var events: EventChannel.EventSink? = null
    private var conversionEvents: EventChannel.EventSink? = null

    private val conversionStream = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
            conversionEvents = sink
        }

        override fun onCancel(arguments: Any?) {
            conversionEvents = null
        }
    }

    init {
        MethodChannel(messenger, "status_studio/render").setMethodCallHandler(this)
        EventChannel(messenger, "status_studio/render/events").setStreamHandler(this)
        EventChannel(messenger, "status_studio/render/conversion").setStreamHandler(conversionStream)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(call, result)
            "convert" -> convert(call, result)
            "join" -> join(call, result)
            "cancelJoin" -> {
                joiner.cancel()
                result.success(null)
            }
            "cancel" -> {
                renderer.cancel()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        if (renderer.isBusy) {
            result.error("busy", "A render is already running.", null)
            return
        }
        val arguments = call.arguments as? Map<*, *>
        if (arguments == null) {
            result.error("bad_spec", "The render spec must be a map.", null)
            return
        }
        try {
            val spec = RenderSpec.fromMap(arguments.entries.associate { it.key.toString() to it.value })
            renderer.start(spec, eventsListener)
            result.success(null)
        } catch (error: IllegalArgumentException) {
            result.error("bad_spec", error.message, null)
        } catch (error: RuntimeException) {
            result.error("start_failed", error.message, null)
        }
    }

    private fun convert(call: MethodCall, result: MethodChannel.Result) {
        val inputPath = call.argument<String>("inputPath")
        val outputPath = call.argument<String>("outputPath")
        if (inputPath == null || outputPath == null) {
            result.error("bad_spec", "convert needs inputPath and outputPath.", null)
            return
        }
        try {
            converter.convert(inputPath, outputPath, conversionListener(outputPath, result))
        } catch (error: RuntimeException) {
            result.error("convert_failed", error.message, null)
        }
    }

    private fun join(call: MethodCall, result: MethodChannel.Result) {
        if (joiner.isBusy) {
            result.error("busy", "A join is already running.", null)
            return
        }
        val arguments = call.arguments as? Map<*, *>
        if (arguments == null) {
            result.error("bad_spec", "The join spec must be a map.", null)
            return
        }
        try {
            val spec = JoinSpec.fromMap(arguments.entries.associate { it.key.toString() to it.value })
            joiner.join(spec, joinListener(spec.outputPath, result))
        } catch (error: IllegalArgumentException) {
            result.error("bad_spec", "${error.javaClass.simpleName}: ${error.message}", null)
        } catch (error: RuntimeException) {
            result.error("join_failed", "${error.javaClass.simpleName}: ${error.message}", null)
        }
    }

    private fun joinListener(outputPath: String, result: MethodChannel.Result) =
        object : ClipJoiner.Listener {
            override fun onProgress(fraction: Double) {
                conversionEvents?.success(mapOf("outputPath" to outputPath, "value" to fraction))
            }

            override fun onDone() = result.success(null)

            override fun onError(message: String) = result.error("join_failed", message, null)
        }

    private fun conversionListener(outputPath: String, result: MethodChannel.Result) =
        object : VideoConverter.Listener {
            override fun onProgress(fraction: Double) {
                conversionEvents?.success(mapOf("outputPath" to outputPath, "value" to fraction))
            }

            override fun onDone() = result.success(null)

            override fun onError(message: String) = result.error("convert_failed", message, null)
        }

    private val eventsListener = object : ReelRenderer.Listener {
        override fun onProgress(fraction: Double) {
            events?.success(mapOf("type" to "progress", "value" to fraction))
        }

        override fun onDone(path: String) {
            events?.success(mapOf("type" to "done", "path" to path))
        }

        override fun onError(message: String) {
            events?.success(mapOf("type" to "error", "message" to message))
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }
}
