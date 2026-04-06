package com.example.remote_assist

import android.content.Intent
import android.provider.Settings
import android.util.DisplayMetrics
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.remote_assist/remote_control"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAccessibilityEnabled" -> {
                        result.success(RemoteControlService.isRunning())
                    }

                    "openAccessibilitySettings" -> {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    }

                    "injectTap" -> {
                        val normX = call.argument<Double>("x") ?: run {
                            result.error("INVALID_ARG", "Missing x coordinate", null)
                            return@setMethodCallHandler
                        }
                        val normY = call.argument<Double>("y") ?: run {
                            result.error("INVALID_ARG", "Missing y coordinate", null)
                            return@setMethodCallHandler
                        }

                        // Convert normalized coordinates (0-1) to actual screen pixels
                        val metrics = DisplayMetrics()
                        windowManager.defaultDisplay.getRealMetrics(metrics)
                        val screenX = (normX * metrics.widthPixels).toFloat()
                        val screenY = (normY * metrics.heightPixels).toFloat()

                        val success = RemoteControlService.injectTap(screenX, screenY)
                        result.success(success)
                    }

                    "getScreenSize" -> {
                        val metrics = DisplayMetrics()
                        windowManager.defaultDisplay.getRealMetrics(metrics)
                        result.success(mapOf(
                            "width" to metrics.widthPixels,
                            "height" to metrics.heightPixels
                        ))
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
