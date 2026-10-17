package com.mystyle.purelive

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The app's own floating window over other apps (A07.25, "应用悬浮窗"): the
 * in-app mini window, or the playing room, goes on floating when the app is
 * left, with the app's own buttons, instead of becoming the system's
 * picture-in-picture. Needs "显示在其他应用的上层" (SYSTEM_ALERT_WINDOW).
 *
 * The app's one Flutter engine (kept by audio_service, it outlives the
 * activity) moves from the activity's view to a small [FlutterView] in a
 * `TYPE_APPLICATION_OVERLAY` window and back, so the player, its picture
 * and the danmaku go on untouched; Dart draws only the mini window while
 * [showing]. The app's lifecycle is not reported meanwhile (the app looks
 * on screen to Dart, which it is).
 *
 * Channel `pure_live/overlay`: `status` (whether the permission is given),
 * `openSettings`, `arm {enabled, x, y, width, height}` (the window's place on
 * the screen in pixels), `enterNow {x, y, width, height}` (the mini window
 * button: to the background now, the window there), `close`, `backToApp`, `dragStart`,
 * `resizeStart {left, top}`; to Dart `changed` (true / false).
 */
object FloatingOverlay {
    const val CHANNEL = "pure_live/overlay"

    private var channel: MethodChannel? = null
    private var engine: FlutterEngine? = null
    private var activity = WeakReference<Activity>(null)

    private var armed = false
    private var armedX = 0
    private var armedY = 0
    private var armedWidth = 0
    private var armedHeight = 0

    // The mini window button's place (`enterNow`): used once, by the next show.
    private var nowX = 0
    private var nowY = 0
    private var nowWidth = 0
    private var nowHeight = 0
    private var now = false

    /** The app is being left with the window armed: lifecycle not reported. */
    var leaving = false
        private set

    /** The floating window shows. */
    var showing = false
        private set

    private var view: FlutterView? = null
    private var params: WindowManager.LayoutParams? = null

    // A drag or resize the Dart side started, followed with raw screen
    // coordinates (the window moves under the finger, so the view's own
    // coordinates cannot).
    private enum class Gesture { NONE, DRAG, RESIZE }

    private var gesture = Gesture.NONE
    private var lastRawX = 0f
    private var lastRawY = 0f
    private var startRawX = 0f
    private var startRawY = 0f
    private var startX = 0
    private var startY = 0
    private var startWidth = 0
    private var startHeight = 0
    private var resizeLeft = false
    private var resizeTop = false

    fun attach(activity: Activity, engine: FlutterEngine) {
        this.activity = WeakReference(activity)
        if (this.engine === engine && channel != null) return
        this.engine = engine
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                val context = this@FloatingOverlay.activity.get()?.applicationContext
                when (call.method) {
                    "status" -> result.success(context != null && permitted(context))
                    "openSettings" -> result.success(context != null && openSettings(context))
                    "arm" -> {
                        armed = call.argument<Boolean>("enabled") ?: false
                        armedX = call.argument<Number>("x")?.toInt() ?: 0
                        armedY = call.argument<Number>("y")?.toInt() ?: 0
                        armedWidth = call.argument<Number>("width")?.toInt() ?: 0
                        armedHeight = call.argument<Number>("height")?.toInt() ?: 0
                        result.success(null)
                    }
                    "enterNow" -> {
                        val host = this@FloatingOverlay.activity.get()
                        if (host == null || !permitted(host)) {
                            result.success(false)
                        } else {
                            nowX = call.argument<Number>("x")?.toInt() ?: 0
                            nowY = call.argument<Number>("y")?.toInt() ?: 0
                            nowWidth = call.argument<Number>("width")?.toInt() ?: 0
                            nowHeight = call.argument<Number>("height")?.toInt() ?: 0
                            now = nowWidth > 0 && nowHeight > 0
                            leaving = now
                            result.success(now && host.moveTaskToBack(true))
                        }
                    }
                    "close" -> {
                        close()
                        result.success(null)
                    }
                    "backToApp" -> result.success(context != null && backToApp(context))
                    "dragStart" -> {
                        startGesture(Gesture.DRAG)
                        result.success(null)
                    }
                    "resizeStart" -> {
                        resizeLeft = call.argument<Boolean>("left") ?: false
                        resizeTop = call.argument<Boolean>("top") ?: false
                        startGesture(Gesture.RESIZE)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun permitted(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

    private fun openSettings(context: Context): Boolean = try {
        context.startActivity(
            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        true
    } catch (_: ActivityNotFoundException) {
        false
    }

    /** Home or recents (`onUserLeaveHint`): the window shows once the activity stops. */
    fun onLeaving(activity: Activity) {
        leaving = now || (armed && armedWidth > 0 && armedHeight > 0 && permitted(activity))
    }

    /** The activity stopped; false when the window did not show (the lifecycle goes on as usual). */
    fun show(activity: Activity): Boolean {
        val engine = engine ?: return false
        if (!leaving || showing) return showing
        val context = activity.applicationContext
        val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val surface = FlutterSurfaceView(context)
        val overlay = FlutterView(context, surface)
        val layout = WindowManager.LayoutParams(
            if (now) nowWidth else armedWidth,
            if (now) nowHeight else armedHeight,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.OPAQUE,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = if (now) nowX else armedX
            y = if (now) nowY else armedY
        }
        now = false
        return try {
            activity.findViewById<FlutterView>(FlutterActivity.FLUTTER_VIEW_ID)?.detachFromFlutterEngine()
            overlay.attachToFlutterEngine(engine)
            overlay.setOnTouchListener { _, event ->
                follow(event)
                false
            }
            windowManager.addView(overlay, layout)
            view = overlay
            params = layout
            showing = true
            engine.lifecycleChannel.appIsResumed()
            channel?.invokeMethod("changed", true)
            true
        } catch (error: RuntimeException) {
            // Refused (the permission was taken away meanwhile): back to the
            // activity's view.
            overlay.detachFromFlutterEngine()
            activity.findViewById<FlutterView>(FlutterActivity.FLUTTER_VIEW_ID)?.attachToFlutterEngine(engine)
            leaving = false
            false
        }
    }

    /** The activity comes back (or a new one starts): the window goes, the activity's view draws again. */
    fun onReturn(activity: Activity) {
        leaving = false
        now = false
        if (!showing) return
        removeWindow()
        engine?.let { activity.findViewById<FlutterView>(FlutterActivity.FLUTTER_VIEW_ID)?.attachToFlutterEngine(it) }
        channel?.invokeMethod("changed", false)
    }

    /** A new activity is created while the window shows: its own view takes the engine. */
    fun onNewActivity() {
        leaving = false
        if (!showing) return
        removeWindow()
        channel?.invokeMethod("changed", false)
    }

    /** The window's ✕: it goes and the app stays in the background. */
    private fun close() {
        leaving = false
        if (!showing) return
        removeWindow()
        val engine = engine ?: return
        activity.get()?.findViewById<FlutterView>(FlutterActivity.FLUTTER_VIEW_ID)?.attachToFlutterEngine(engine)
        channel?.invokeMethod("changed", false)
        engine.lifecycleChannel.appIsPaused()
    }

    private fun removeWindow() {
        val overlay = view
        view = null
        params = null
        showing = false
        gesture = Gesture.NONE
        if (overlay == null) return
        overlay.setOnTouchListener(null)
        overlay.detachFromFlutterEngine()
        val windowManager = overlay.context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        try {
            windowManager.removeView(overlay)
        } catch (_: IllegalArgumentException) {
            // Already gone.
        }
    }

    private fun backToApp(context: Context): Boolean = try {
        context.startActivity(
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
        )
        true
    } catch (_: ActivityNotFoundException) {
        false
    }

    private fun startGesture(kind: Gesture) {
        val layout = params ?: return
        gesture = kind
        startRawX = lastRawX
        startRawY = lastRawY
        startX = layout.x
        startY = layout.y
        startWidth = layout.width
        startHeight = layout.height
    }

    private fun follow(event: MotionEvent) {
        lastRawX = event.rawX
        lastRawY = event.rawY
        val layout = params ?: return
        val overlay = view ?: return
        when (event.actionMasked) {
            MotionEvent.ACTION_MOVE -> when (gesture) {
                Gesture.DRAG -> {
                    layout.x = startX + (event.rawX - startRawX).roundToInt()
                    layout.y = startY + (event.rawY - startRawY).roundToInt()
                    update(overlay, layout)
                }
                Gesture.RESIZE -> {
                    val dx = (event.rawX - startRawX).roundToInt()
                    val metrics = overlay.resources.displayMetrics
                    val smallest = (160 * metrics.density).roundToInt()
                    val largest = min(metrics.widthPixels, metrics.heightPixels)
                    val width = (startWidth + if (resizeLeft) -dx else dx).coerceIn(smallest, max(smallest, largest))
                    val height = (width.toFloat() * startHeight / max(1, startWidth)).roundToInt()
                    layout.width = width
                    layout.height = height
                    if (resizeLeft) layout.x = startX + startWidth - width
                    if (resizeTop) layout.y = startY + startHeight - height
                    update(overlay, layout)
                }
                Gesture.NONE -> Unit
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (gesture != Gesture.NONE) {
                    gesture = Gesture.NONE
                    keepOnScreen(overlay, layout)
                }
            }
        }
    }

    private fun keepOnScreen(overlay: FlutterView, layout: WindowManager.LayoutParams) {
        val metrics = overlay.resources.displayMetrics
        layout.x = layout.x.coerceIn(0, max(0, metrics.widthPixels - layout.width))
        layout.y = layout.y.coerceIn(0, max(0, metrics.heightPixels - layout.height))
        update(overlay, layout)
    }

    private fun update(overlay: FlutterView, layout: WindowManager.LayoutParams) {
        val windowManager = overlay.context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        try {
            windowManager.updateViewLayout(overlay, layout)
        } catch (_: IllegalArgumentException) {
            // The window went meanwhile.
        }
    }
}
