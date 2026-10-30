package com.hotmail.arehmananis.statusstudio

import com.hotmail.arehmananis.statusstudio.render.RenderChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RenderChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }
}
