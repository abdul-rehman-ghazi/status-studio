package com.hotmail.arehmananis.statusstudio

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import com.hotmail.arehmananis.statusstudio.render.RenderChannel
import com.hotmail.arehmananis.statusstudio.videoin.VideoInChannel
import com.hotmail.arehmananis.statusstudio.videoin.shouldHandleIntent
import com.hotmail.arehmananis.statusstudio.youtube.YtDlpChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var videoIn: VideoInChannel? = null

    // When Android restores the activity after the process died, `intent` is still the
    // original share, which was already handled.
    private var restoredBySystem = false

    override fun onCreate(savedInstanceState: Bundle?) {
        restoredBySystem = savedInstanceState != null
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handOverShare(intent, launchedFromSavedState = false)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        videoIn?.dispose()
        videoIn = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        RenderChannel(applicationContext, messenger)
        YtDlpChannel(applicationContext, messenger)
        videoIn = VideoInChannel(applicationContext, messenger)
        handOverShare(intent, restoredBySystem)
        MethodChannel(messenger, "status_studio/system").setMethodCallHandler { call, result ->
            when (call.method) {
                "openAppSettings" -> {
                    openAppSettings()
                    result.success(null)
                }
                "processorName" -> result.success(processorName())
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Android keeps the launch intent and replays it when the app is reopened from Recents, or
     * when this method runs again for a new engine. A taken share is therefore emptied.
     */
    private fun handOverShare(shareIntent: Intent, launchedFromSavedState: Boolean) {
        if (!shouldHandleIntent(shareIntent.flags, launchedFromSavedState)) return
        if (videoIn?.receive(shareIntent) != true) return
        shareIntent.action = Intent.ACTION_MAIN
        shareIntent.setDataAndType(null, null)
        shareIntent.clipData = null
        shareIntent.replaceExtras(Bundle())
    }

    /**
     * For support messages (spec FR-31). The chip's maker and model exist only from Android 12;
     * before that, and on phones that leave them unknown, the hardware name is the best there is.
     */
    private fun processorName(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return Build.HARDWARE
        if (Build.SOC_MODEL == Build.UNKNOWN) return Build.HARDWARE
        return "${Build.SOC_MANUFACTURER} ${Build.SOC_MODEL}"
    }

    /** The app's page in system Settings, where a refused permission can be granted. */
    private fun openAppSettings() {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", packageName, null),
        )
        startActivity(intent)
    }
}
