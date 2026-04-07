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

                    "injectSwipe" -> {
                        val normStartX = call.argument<Double>("startX") ?: run {
                            result.error("INVALID_ARG", "Missing startX coordinate", null)
                            return@setMethodCallHandler
                        }
                        val normStartY = call.argument<Double>("startY") ?: run {
                            result.error("INVALID_ARG", "Missing startY coordinate", null)
                            return@setMethodCallHandler
                        }
                        val normEndX = call.argument<Double>("endX") ?: run {
                            result.error("INVALID_ARG", "Missing endX coordinate", null)
                            return@setMethodCallHandler
                        }
                        val normEndY = call.argument<Double>("endY") ?: run {
                            result.error("INVALID_ARG", "Missing endY coordinate", null)
                            return@setMethodCallHandler
                        }
                        val durationMs = call.argument<Int>("duration") ?: 300

                        // Convert normalized coordinates (0-1) to actual screen pixels
                        val metrics = DisplayMetrics()
                        windowManager.defaultDisplay.getRealMetrics(metrics)
                        val screenStartX = (normStartX * metrics.widthPixels).toFloat()
                        val screenStartY = (normStartY * metrics.heightPixels).toFloat()
                        val screenEndX = (normEndX * metrics.widthPixels).toFloat()
                        val screenEndY = (normEndY * metrics.heightPixels).toFloat()

                        val success = RemoteControlService.injectSwipe(
                            screenStartX, screenStartY,
                            screenEndX, screenEndY,
                            durationMs.toLong()
                        )
                        result.success(success)
                    }

                    "injectLongPress" -> {
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

                        val success = RemoteControlService.injectLongPress(screenX, screenY)
                        result.success(success)
                    }

                    "cancelGesture" -> {
                        val success = RemoteControlService.cancelGesture()
                        result.success(success)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
