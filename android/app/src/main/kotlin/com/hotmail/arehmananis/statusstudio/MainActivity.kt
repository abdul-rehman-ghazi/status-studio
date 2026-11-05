package com.hotmail.arehmananis.statusstudio

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import com.hotmail.arehmananis.statusstudio.render.RenderChannel
import com.hotmail.arehmananis.statusstudio.videoin.VideoInChannel
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
        videoIn?.receive(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        RenderChannel(applicationContext, messenger)
        YtDlpChannel(applicationContext, messenger)
        videoIn = VideoInChannel(applicationContext, messenger)
        if (!restoredBySystem) videoIn?.receive(intent)
        MethodChannel(messenger, "status_studio/system").setMethodCallHandler { call, result ->
            when (call.method) {
                "openAppSettings" -> {
                    openAppSettings()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
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
