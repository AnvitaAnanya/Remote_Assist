package com.example.remote_assist

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.DisplayMetrics
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.remote_assist/remote_control"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        // Wire the floating button's click callback to Flutter
        FloatingButtonService.onButtonClicked = {
            Log.i("MainActivity", "Floating button clicked → notifying Flutter")
            runOnUiThread {
                methodChannel?.invokeMethod("onFloatingButtonClicked", null)
            }
        }

        methodChannel!!.setMethodCallHandler { call, result ->
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

                    "canDrawOverlays" -> {
                        val canDraw = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            Settings.canDrawOverlays(this)
                        } else {
                            true // pre-M doesn't need explicit permission
                        }
                        result.success(canDraw)
                    }

                    "requestOverlayPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        }
                        result.success(true)
                    }

                    "showFloatingButton" -> {
                        val canDraw = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            Settings.canDrawOverlays(this)
                        } else {
                            true
                        }
                        if (canDraw) {
                            val intent = Intent(this, FloatingButtonService::class.java)
                            startService(intent)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }

                    "hideFloatingButton" -> {
                        val intent = Intent(this, FloatingButtonService::class.java)
                        stopService(intent)
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

                    "injectDragStart" -> {
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

                        val success = RemoteControlService.injectDragStart(screenX, screenY)
                        result.success(success)
                    }

                    "injectDragUpdate" -> {
                        val normX = call.argument<Double>("x") ?: run {
                            result.error("INVALID_ARG", "Missing x coordinate", null)
                            return@setMethodCallHandler
                        }
                        val normY = call.argument<Double>("y") ?: run {
                            result.error("INVALID_ARG", "Missing y coordinate", null)
                            return@setMethodCallHandler
                        }

                        val metrics = DisplayMetrics()
                        windowManager.defaultDisplay.getRealMetrics(metrics)
                        val screenX = (normX * metrics.widthPixels).toFloat()
                        val screenY = (normY * metrics.heightPixels).toFloat()

                        val success = RemoteControlService.injectDragUpdate(screenX, screenY)
                        result.success(success)
                    }

                    "injectDragEnd" -> {
                        val normX = call.argument<Double>("x") ?: run {
                            result.error("INVALID_ARG", "Missing x coordinate", null)
                            return@setMethodCallHandler
                        }
                        val normY = call.argument<Double>("y") ?: run {
                            result.error("INVALID_ARG", "Missing y coordinate", null)
                            return@setMethodCallHandler
                        }

                        val metrics = DisplayMetrics()
                        windowManager.defaultDisplay.getRealMetrics(metrics)
                        val screenX = (normX * metrics.widthPixels).toFloat()
                        val screenY = (normY * metrics.heightPixels).toFloat()

                        val success = RemoteControlService.injectDragEnd(screenX, screenY)
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
