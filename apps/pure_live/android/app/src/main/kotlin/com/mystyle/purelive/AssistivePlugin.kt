package com.mystyle.purelive

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `pure_live/assistive` (docs/R-性能和流畅度/R01-基准和测量/R01.3-真实操作的掉帧):
 * whether someone uses the screen through an assistive tool, so the app
 * gives Flutter's semantics tree only then.
 *
 * Android turns Flutter's semantics on for any accessibility service, and
 * Flutter's own `accessibleNavigation` turns true as soon as a service
 * reads one node: HyperOS's 小米澎湃AI引擎 (on by default) does, and then
 * keeping the tree took more of each frame than layout and paint. Here an
 * assistive tool is touch exploration (TalkBack and other screen readers)
 * or Switch Access or Voice Access.
 * - `state`: that, now;
 * - `changed(bool)` to Dart whenever it changes.
 */
internal class AssistivePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    companion object {
        private const val CHANNEL = "pure_live/assistive"

        // Services that act on the screen's contents without touch
        // exploration.
        private val TOOLS = listOf("switchaccess", "voiceaccess")

        fun inUse(manager: AccessibilityManager): Boolean {
            if (!manager.isEnabled) return false
            if (manager.isTouchExplorationEnabled) return true
            return manager.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK).any { info ->
                val id = info.id.lowercase()
                TOOLS.any { id.contains(it) }
            }
        }
    }

    private var channel: MethodChannel? = null
    private var manager: AccessibilityManager? = null
    private var last: Boolean? = null
    private val main = Handler(Looper.getMainLooper())

    private val stateListener = AccessibilityManager.AccessibilityStateChangeListener { publish() }
    private val touchListener = AccessibilityManager.TouchExplorationStateChangeListener { publish() }
    private var servicesListener: Any? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val am = binding.applicationContext.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
        manager = am
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
        am.addAccessibilityStateChangeListener(stateListener)
        am.addTouchExplorationStateChangeListener(touchListener)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val listener = AccessibilityManager.AccessibilityServicesStateChangeListener { publish() }
            am.addAccessibilityServicesStateChangeListener(binding.applicationContext.mainExecutor, listener)
            servicesListener = listener
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        manager?.let { am ->
            am.removeAccessibilityStateChangeListener(stateListener)
            am.removeTouchExplorationStateChangeListener(touchListener)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                (servicesListener as? AccessibilityManager.AccessibilityServicesStateChangeListener)?.let {
                    am.removeAccessibilityServicesStateChangeListener(it)
                }
            }
        }
        servicesListener = null
        channel?.setMethodCallHandler(null)
        channel = null
        manager = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "state" -> {
                val now = manager?.let(::inUse) ?: false
                last = now
                result.success(now)
            }

            else -> result.notImplemented()
        }
    }

    private fun publish() {
        val am = manager ?: return
        val now = inUse(am)
        if (now == last) return
        last = now
        main.post { channel?.invokeMethod("changed", now) }
    }
}
