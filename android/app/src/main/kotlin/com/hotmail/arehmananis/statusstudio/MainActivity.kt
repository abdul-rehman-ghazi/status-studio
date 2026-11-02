package com.hotmail.arehmananis.statusstudio

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import com.hotmail.arehmananis.statusstudio.render.RenderChannel
import com.hotmail.arehmananis.statusstudio.youtube.YtDlpChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        RenderChannel(applicationContext, messenger)
        YtDlpChannel(applicationContext, messenger)
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
