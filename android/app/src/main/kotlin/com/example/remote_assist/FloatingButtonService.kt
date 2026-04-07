package com.example.remote_assist

import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView

/**
 * A system overlay service that displays a small draggable orange button
 * on top of all apps. When tapped it fires the [onButtonClicked] callback
 * so Flutter can revoke remote control.
 *
 * The button snaps to the nearest screen edge when released.
 */
class FloatingButtonService : Service() {

    companion object {
        private const val TAG = "FloatingButtonService"
        private const val BUTTON_SIZE_DP = 48

        /** Callback invoked (on main thread) when the elder taps the button. */
        var onButtonClicked: (() -> Unit)? = null
    }

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var layoutParams: WindowManager.LayoutParams? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "FloatingButtonService created")

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        val density = resources.displayMetrics.density
        val sizePx = (BUTTON_SIZE_DP * density).toInt()

        // Create the button view programmatically (no XML layout needed)
        val button = ImageView(this).apply {
            // Orange circle background
            val circle = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xFFF57C00.toInt()) // Material Orange 700
            }
            background = circle

            // Remote control icon (touch_app from Material)
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            // Use a hand/touch icon via a unicode fallback — we'll draw it as text instead
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            setPadding(
                (8 * density).toInt(),
                (8 * density).toInt(),
                (8 * density).toInt(),
                (8 * density).toInt()
            )
            setColorFilter(0xFFFFFFFF.toInt()) // white tint
            elevation = 8 * density
        }

        floatingView = button

        // Window layout params — overlay on top of everything
        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        layoutParams = WindowManager.LayoutParams(
            sizePx,
            sizePx,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 0  // start at top-left
            y = (200 * density).toInt()
        }

        windowManager?.addView(floatingView, layoutParams)

        // ── Touch handling: drag + tap ──────────────────────────────────────
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var isDragging = false

        button.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = layoutParams!!.x
                    initialY = layoutParams!!.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isDragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (Math.abs(dx) > 10 || Math.abs(dy) > 10) {
                        isDragging = true
                    }
                    layoutParams!!.x = initialX + dx.toInt()
                    layoutParams!!.y = initialY + dy.toInt()
                    windowManager?.updateViewLayout(floatingView, layoutParams)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!isDragging) {
                        // It was a tap — revoke remote control
                        Log.i(TAG, "Floating button tapped → revoking")
                        onButtonClicked?.invoke()
                    } else {
                        // Snap to nearest edge
                        snapToEdge()
                    }
                    true
                }
                else -> false
            }
        }
    }

    /**
     * Snaps the button to the nearest screen edge (left, right, top, bottom)
     * while keeping the perpendicular coordinate unchanged.
     */
    private fun snapToEdge() {
        val params = layoutParams ?: return
        val dm = resources.displayMetrics
        val screenW = dm.widthPixels
        val screenH = dm.heightPixels
        val density = dm.density
        val sizePx = (BUTTON_SIZE_DP * density).toInt()
        val margin = (4 * density).toInt()

        val centerX = params.x + sizePx / 2
        val centerY = params.y + sizePx / 2

        // Distances to each edge
        val distLeft = centerX
        val distRight = screenW - centerX
        val distTop = centerY
        val distBottom = screenH - centerY

        val minDist = minOf(distLeft, distRight, distTop, distBottom)

        when (minDist) {
            distLeft -> params.x = margin
            distRight -> params.x = screenW - sizePx - margin
            distTop -> params.y = margin
            distBottom -> params.y = screenH - sizePx - margin
        }

        windowManager?.updateViewLayout(floatingView, params)
    }

    override fun onDestroy() {
        Log.i(TAG, "FloatingButtonService destroyed")
        if (floatingView != null) {
            windowManager?.removeView(floatingView)
            floatingView = null
        }
        super.onDestroy()
    }
}
