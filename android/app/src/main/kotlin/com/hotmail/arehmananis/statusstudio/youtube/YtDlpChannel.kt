package com.hotmail.arehmananis.statusstudio.youtube

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * `status_studio/ytdlp`: `quickVideoInfo(videoId)` and `videoInfo(videoId)` return yt-dlp's `-J`
 * JSON, without and with solving YouTube's JavaScript challenges; `update()` returns
 * `updated` or `up_to_date`, `version()` the yt-dlp version. Failures come back as
 * `ytdlp_failed` with yt-dlp's error output as the message.
 */
class YtDlpChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {
    // One thread: yt-dlp runs as a Python process and the first call unpacks Python.
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var initialized = false

    init {
        MethodChannel(messenger, "status_studio/ytdlp").setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "quickVideoInfo" -> withVideoId(call, result) { videoInfo(it, ::quickVideoInfoOptions) }
            "videoInfo" -> withVideoId(call, result) { videoInfo(it, ::videoInfoOptions) }
            "update" -> runInBackground(result) { update() }
            "version" -> runInBackground(result) { version() }
            else -> result.notImplemented()
        }
    }

    private fun withVideoId(
        call: MethodCall,
        result: MethodChannel.Result,
        work: (String) -> String,
    ) {
        val videoId = call.arguments as? String
        if (videoId == null) {
            result.error("bad_args", "${call.method} needs a video ID.", null)
            return
        }
        runInBackground(result) { work(videoId) }
    }

    private fun runInBackground(result: MethodChannel.Result, work: () -> Any) {
        worker.execute {
            try {
                val value = work()
                mainHandler.post { result.success(value) }
            } catch (error: YoutubeDLException) {
                mainHandler.post { result.error("ytdlp_failed", error.message, null) }
            } catch (error: InterruptedException) {
                mainHandler.post { result.error("ytdlp_failed", error.message, null) }
            } catch (error: RuntimeException) {
                mainHandler.post { result.error("ytdlp_failed", error.message, null) }
            }
        }
    }

    /** Runs on the worker thread only, so the one-time init needs no lock. */
    private fun ytDlp(): YoutubeDL {
        val youtubeDl = YoutubeDL.getInstance()
        if (!initialized) {
            youtubeDl.init(context)
            initialized = true
        }
        return youtubeDl
    }

    /** Commands go after the library's own options, so `--no-js-runtimes` overrides its QuickJS. */
    private fun videoInfo(videoId: String, options: (String) -> List<String>): String {
        val request = YoutubeDLRequest(videoUrl(videoId))
        request.addCommands(options("${context.cacheDir.absolutePath}/yt-dlp"))
        return ytDlp().execute(request).out
    }

    /** Asks yt-dlp itself: the library only knows the version after it has updated once. */
    private fun version(): String {
        val request = YoutubeDLRequest(emptyList<String>())
        request.addOption("--version")
        return ytDlp().execute(request).out.trim()
    }

    private fun update(): String =
        when (ytDlp().updateYoutubeDL(context, YoutubeDL.UpdateChannel._STABLE)) {
            YoutubeDL.UpdateStatus.DONE -> "updated"
            else -> "up_to_date"
        }
}
