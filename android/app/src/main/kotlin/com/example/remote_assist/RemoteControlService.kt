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
         * Start a continued gesture (finger down) at the given coordinates.
         * The finger stays pressed until [injectDragUpdate] or [injectDragEnd] is called.
         * Used for both long-press-and-hold and drag-and-drop.
         * Returns true if the gesture was dispatched successfully.
         */
        fun injectDragStart(x: Float, y: Float): Boolean {
            val service = instance ?: run {
                Log.w(TAG, "Service not running — cannot inject drag start")
                return false
            }
            return service.performDragStart(x, y)
        }

        /**
         * Continue an ongoing drag gesture to a new position.
         * The finger stays pressed (willContinue = true).
         * Returns true if the gesture was dispatched successfully.
         */
        fun injectDragUpdate(x: Float, y: Float): Boolean {
            val service = instance ?: run {
                Log.w(TAG, "Service not running — cannot inject drag update")
                return false
            }
            return service.performDragUpdate(x, y)
        }

        /**
         * End a continued gesture at the given coordinates (lifts the finger).
         * Used to release a long press or drop a dragged item.
         * Returns true if the gesture was dispatched successfully.
         */
        fun injectDragEnd(x: Float, y: Float): Boolean {
            val service = instance ?: run {
                Log.w(TAG, "Service not running — cannot inject drag end")
                return false
            }
            return service.performDragEnd(x, y)
        }

        /**
         * Cancel any gesture currently in progress (safety fallback).
         * Dispatching a new gesture automatically cancels the ongoing one.
         */
        fun cancelGesture(): Boolean {
            val service = instance ?: run {
                Log.w(TAG, "Service not running — cannot cancel gesture")
                return false
            }
            return service.performCancelGesture()
        }

        /**
         * Check if the service is currently running.
         */
        fun isRunning(): Boolean = instance != null
    }

    // ─── Continued stroke state ────────────────────────────────────────────────
    // Tracks the last StrokeDescription so we can call continueStroke() on it.
    private var lastStroke: GestureDescription.StrokeDescription? = null

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
        lastStroke = null
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

        // A tap cancels any ongoing continued gesture
        lastStroke = null

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

        // A swipe cancels any ongoing continued gesture
        lastStroke = null

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

    /**
     * Starts a continued gesture at (x, y) — the finger touches down and stays pressed.
     * Call [performDragUpdate] to move the finger, or [performDragEnd] to lift it.
     * Uses willContinue = true (API 26+).
     */
    private fun performDragStart(x: Float, y: Float): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            Log.w(TAG, "Continued strokes require API 26+, falling back to long press")
            return performLongPressFallback(x, y)
        }

        // Cancel any previous continued gesture
        lastStroke = null

        val path = Path()
        path.moveTo(x, y)

        // Hold at this point for 500ms to register as a long press, keep finger down
        val stroke = GestureDescription.StrokeDescription(
            path, 0, 500, true  // willContinue = true → finger stays down
        )

        val gesture = GestureDescription.Builder()
            .addStroke(stroke)
            .build()

        val dispatched = dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                Log.d(TAG, "Drag start dispatched at ($x, $y), waiting for continuation")
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                Log.w(TAG, "Drag start cancelled at ($x, $y)")
                lastStroke = null
            }
        }, null)

        if (dispatched) {
            lastStroke = stroke
        } else {
            Log.w(TAG, "dispatchGesture returned false for drag start at ($x, $y)")
            lastStroke = null
        }
        return dispatched
    }

    /**
     * Continues an ongoing drag gesture to a new position (x, y).
     * The finger stays pressed (willContinue = true).
     */
    private fun performDragUpdate(x: Float, y: Float): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            Log.w(TAG, "Continued strokes require API 26+")
            return false
        }

        val previousStroke = lastStroke
        if (previousStroke == null) {
            Log.w(TAG, "No ongoing drag to update — did dragStart get called?")
            return false
        }

        val path = Path()
        path.moveTo(x, y)

        val continuation = previousStroke.continueStroke(
            path, 0, 100, true  // willContinue = true → finger still down
        )

        val gesture = GestureDescription.Builder()
            .addStroke(continuation)
            .build()

        val dispatched = dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                Log.d(TAG, "Drag update to ($x, $y)")
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                Log.w(TAG, "Drag update cancelled at ($x, $y)")
                lastStroke = null
            }
        }, null)

        if (dispatched) {
            lastStroke = continuation
        } else {
            Log.w(TAG, "dispatchGesture returned false for drag update to ($x, $y)")
            lastStroke = null
        }
        return dispatched
    }

    /**
     * Ends a continued gesture at (x, y) — lifts the finger.
     * Completes a long press release or drops a dragged item.
     */
    private fun performDragEnd(x: Float, y: Float): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            Log.w(TAG, "Continued strokes require API 26+, using cancel fallback")
            return performCancelGesture()
        }

        val previousStroke = lastStroke
        if (previousStroke == null) {
            Log.w(TAG, "No ongoing drag to end — ignoring")
            return true
        }

        val path = Path()
        path.moveTo(x, y)

        val finalStroke = previousStroke.continueStroke(
            path, 0, 50, false  // willContinue = false → finger lifts
        )

        val gesture = GestureDescription.Builder()
            .addStroke(finalStroke)
            .build()

        lastStroke = null

        val dispatched = dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                Log.d(TAG, "Drag end at ($x, $y) — finger lifted")
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                Log.w(TAG, "Drag end cancelled at ($x, $y)")
            }
        }, null)

        if (!dispatched) {
            Log.w(TAG, "dispatchGesture returned false for drag end at ($x, $y)")
        }
        return dispatched
    }

    /**
     * Fallback long press for API < 26 (no willContinue support).
     * Holds for 2 seconds then auto-releases.
     */
    private fun performLongPressFallback(x: Float, y: Float): Boolean {
        val path = Path()
        path.moveTo(x, y)

        val stroke = GestureDescription.StrokeDescription(path, 0, 2000)
        val gesture = GestureDescription.Builder()
            .addStroke(stroke)
            .build()

        return dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                Log.d(TAG, "Fallback long press completed at ($x, $y)")
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                Log.w(TAG, "Fallback long press cancelled at ($x, $y)")
            }
        }, null)
    }

    /**
     * Cancels any ongoing gesture by dispatching a minimal gesture.
     * Android's dispatchGesture automatically cancels any in-progress gesture.
     * Fixed: uses valid coordinates (0, 0) instead of invalid (-1, -1).
     */
    private fun performCancelGesture(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            return false
        }

        lastStroke = null

        val path = Path()
        path.moveTo(0f, 0f)  // valid coordinates (top-left corner)

        val stroke = GestureDescription.StrokeDescription(path, 0, 1)
        val gesture = GestureDescription.Builder()
            .addStroke(stroke)
            .build()

        val dispatched = dispatchGesture(gesture, null, null)
        Log.d(TAG, "Cancel gesture dispatched: $dispatched")
        return dispatched
    }
}
