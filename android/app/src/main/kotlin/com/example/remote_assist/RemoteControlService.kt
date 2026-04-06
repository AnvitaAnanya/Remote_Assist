package com.example.remote_assist

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Build
import android.util.Log
import android.view.accessibility.AccessibilityEvent

/**
 * Accessibility Service that can inject touch gestures on the elder's device.
 * Used by the remote control feature so the caregiver can tap on the elder's screen.
 *
 * The elder must enable this service in Settings → Accessibility → Remote Assist.
 */
class RemoteControlService : AccessibilityService() {

    companion object {
        private const val TAG = "RemoteControlService"

        // Static reference so Flutter can reach the running service instance
        var instance: RemoteControlService? = null
            private set

        /**
         * Dispatch a tap gesture at the given screen coordinates.
         * Returns true if the gesture was dispatched successfully.
         */
        fun injectTap(x: Float, y: Float): Boolean {
            val service = instance ?: run {
                Log.w(TAG, "Service not running — cannot inject tap")
                return false
            }
            return service.performTap(x, y)
        }

        /**
         * Dispatch a swipe gesture from (startX, startY) to (endX, endY)
         * over the given duration in milliseconds.
         * Returns true if the gesture was dispatched successfully.
         */
        fun injectSwipe(
            startX: Float, startY: Float,
            endX: Float, endY: Float,
            durationMs: Long
        ): Boolean {
            val service = instance ?: run {
                Log.w(TAG, "Service not running — cannot inject swipe")
                return false
            }
            return service.performSwipe(startX, startY, endX, endY, durationMs)
        }

        /**
         * Check if the service is currently running.
         */
        fun isRunning(): Boolean = instance != null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.i(TAG, "RemoteControlService connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // We don't need to process accessibility events — we only use this
        // service for dispatchGesture().
    }

    override fun onInterrupt() {
        Log.w(TAG, "RemoteControlService interrupted")
    }

    override fun onDestroy() {
        instance = null
        Log.i(TAG, "RemoteControlService destroyed")
        super.onDestroy()
    }

    /**
     * Performs a tap gesture at (x, y) screen coordinates using dispatchGesture.
     * Available on API 24+ (Android 7+).
     */
    private fun performTap(x: Float, y: Float): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            Log.w(TAG, "dispatchGesture requires API 24+")
            return false
        }

        val path = Path()
        path.moveTo(x, y)

        val stroke = GestureDescription.StrokeDescription(
            path,
            0,    // startTime (ms) — start immediately
            50    // duration (ms) — short tap
        )

        val gesture = GestureDescription.Builder()
            .addStroke(stroke)
            .build()

        val dispatched = dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                Log.d(TAG, "Tap dispatched at ($x, $y)")
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                Log.w(TAG, "Tap cancelled at ($x, $y)")
            }
        }, null)

        if (!dispatched) {
            Log.w(TAG, "dispatchGesture returned false for ($x, $y)")
        }
        return dispatched
    }

    /**
     * Performs a swipe gesture from (startX, startY) to (endX, endY)
     * over the given duration using dispatchGesture.
     * Available on API 24+ (Android 7+).
     */
    private fun performSwipe(
        startX: Float, startY: Float,
        endX: Float, endY: Float,
        durationMs: Long
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            Log.w(TAG, "dispatchGesture requires API 24+")
            return false
        }

        // Clamp duration to a sane range (50ms – 2000ms)
        val clampedDuration = durationMs.coerceIn(50, 2000)

        val path = Path()
        path.moveTo(startX, startY)
        path.lineTo(endX, endY)

        val stroke = GestureDescription.StrokeDescription(
            path,
            0,               // startTime (ms) — start immediately
            clampedDuration  // duration matches the caregiver's swipe speed
        )

        val gesture = GestureDescription.Builder()
            .addStroke(stroke)
            .build()

        val dispatched = dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                Log.d(TAG, "Swipe dispatched ($startX,$startY) → ($endX,$endY) in ${clampedDuration}ms")
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                Log.w(TAG, "Swipe cancelled ($startX,$startY) → ($endX,$endY)")
            }
        }, null)

        if (!dispatched) {
            Log.w(TAG, "dispatchGesture returned false for swipe ($startX,$startY) → ($endX,$endY)")
        }
        return dispatched
    }
}
