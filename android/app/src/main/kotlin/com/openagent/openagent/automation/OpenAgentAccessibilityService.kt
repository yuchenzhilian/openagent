package com.openagent.openagent.automation

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import kotlin.math.max
import kotlin.math.min

/**
 * OpenAgent's Accessibility Service (L1 基础自动化层).
 *
 * Exposed to Dart via [AutomationBridge]. The service MUST be enabled by the
 * end-user in Android Settings → Accessibility before any calls here will
 * succeed (the Dart-side Permission Guide page deep-links into Settings).
 *
 * Design notes
 * ------------
 * All methods return a Boolean status so Dart can fall back to L2 (Shizuku)
 * on failure. Long-running actions (dispatchGesture / multistep) are posted
 * back to the main looper because AccessibilityService callbacks MUST run on
 * the service's main thread.
 */
class OpenAgentAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "OAAccessService"

        /** Latest bound instance, set by the system on bind/unbind. */
        @Volatile
        private var INSTANCE: OpenAgentAccessibilityService? = null

        /** 安全模式标记 — 开启时跳过所有手势执行（银行/支付类 App 在前台时使用）。 */
        @Volatile
        private var safeModeEnabled = false

        fun isServiceConnected(): Boolean = INSTANCE?.serviceConnected == true

        fun requireInstance(): OpenAgentAccessibilityService? =
            if (INSTANCE?.serviceConnected == true) INSTANCE else null

        /** 设置安全模式。由 AutomationChannel 调用。 */
        fun setSafeMode(enabled: Boolean) {
            safeModeEnabled = enabled
            Log.i(TAG, "Safe mode ${if (enabled) "ENABLED" else "DISABLED"}")
        }

        /** 查询安全模式是否开启。点击/手势方法在执行前检查此值。 */
        fun isSafeMode(): Boolean = safeModeEnabled
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var serviceConnected = false

    // ---- Service lifecycle -------------------------------------------------

    override fun onServiceConnected() {
        super.onServiceConnected()
        serviceConnected = true
        INSTANCE = this
        Log.i(TAG, "Accessibility service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // We do not react to events currently — actions are pull-based from
        // the Agent runtime. This hook is required by the abstract base class.
    }

    override fun onInterrupt() = Unit

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        serviceConnected = false
        INSTANCE = null
        Log.i(TAG, "Accessibility service disconnected")
        return super.onUnbind(intent)
    }

    // ---- Public API (invoked by AutomationBridge via mainHandler) ---------

    fun clickByText(text: String, exactMatch: Boolean = true): Boolean {
        require(serviceConnected) { "service not connected" }
        if (safeModeEnabled) {
            Log.w(TAG, "clickByText blocked: safe mode enabled")
            return false
        }
        val node = findFirst(rootInActiveWindow) { n ->
            val t = n.text?.toString().orEmpty()
            val cd = n.contentDescription?.toString().orEmpty()
            if (exactMatch) t == text || cd == text
            else t.contains(text) || cd.contains(text)
        }
        if (node == null) {
            Log.w(TAG, "clickByText: no node matching '$text'")
            return false
        }
        var ok = node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        // --- Fallback: many WeChat/Douyin buttons mark text children as
        // non-clickable, so ACTION_CLICK returns false even though the
        // PARENT node is clickable. Try gesture-tapping the centre of the
        // node's on-screen bounds (same as human would tap). ---
        if (!ok && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val r = Rect()
            runCatching { node.getBoundsInScreen(r) }
            if (r.width() > 0 && r.height() > 0) {
                val cx = (r.left + r.right) / 2
                val cy = (r.top + r.bottom) / 2
                Log.d(TAG, "clickByText: ACTION_CLICK failed, fallback gesture tap ($cx,$cy)")
                ok = clickAtCoords(cx, cy)
            }
        }
        node.recycle()
        Log.d(TAG, "clickByText($text) -> $ok")
        return ok
    }

    fun clickById(viewId: String): Boolean {
        require(serviceConnected) { "service not connected" }
        if (safeModeEnabled) {
            Log.w(TAG, "clickById blocked: safe mode enabled")
            return false
        }
        val matches = rootInActiveWindow
            ?.findAccessibilityNodeInfosByViewId(viewId)
            .orEmpty()
        val node = matches.firstOrNull { it.isClickable } ?: matches.firstOrNull()
        if (node == null) {
            Log.w(TAG, "clickById: no node with id='$viewId'")
            return false
        }
        var ok = node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        if (!ok && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val r = Rect()
            runCatching { node.getBoundsInScreen(r) }
            if (r.width() > 0 && r.height() > 0) {
                val cx = (r.left + r.right) / 2
                val cy = (r.top + r.bottom) / 2
                Log.d(TAG, "clickById: ACTION_CLICK failed, fallback gesture tap ($cx,$cy)")
                ok = clickAtCoords(cx, cy)
            }
        }
        node.recycle()
        matches.forEach { if (it != node) it.recycle() }
        Log.d(TAG, "clickById($viewId) -> $ok")
        return ok
    }

    /** Clicks the centre of [bounds] using dispatchGesture, so it works even
     *  for non-clickable parents. Used as the L1 fallback for "click by text/id"
     *  failures where the node exists but isn't ACTION_CLICK-friendly.
     *  Coordinates are in screen pixels. */
    fun clickAtCoords(x: Int, y: Int): Boolean {
        require(serviceConnected) { "service not connected" }
        if (safeModeEnabled) {
            Log.w(TAG, "clickAtCoords blocked: safe mode enabled")
            return false
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 60L))
            .build()
        val latch = java.util.concurrent.atomic.AtomicBoolean(false)
        val callback = object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                latch.set(true)
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                latch.set(false)
            }
        }
        return runCatching {
            dispatchGesture(gesture, callback, mainHandler)
            // Block at most 500 ms; most taps complete faster.
            val deadline = System.currentTimeMillis() + 500
            while (System.currentTimeMillis() < deadline && !latch.get()) {
                Thread.sleep(10)
            }
            latch.get()
        }.getOrDefault(false)
    }

    fun swipe(x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Long): Boolean {
        require(serviceConnected) { "service not connected" }
        if (safeModeEnabled) {
            Log.w(TAG, "swipe blocked: safe mode enabled")
            return false
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val path = Path().apply { moveTo(x1.toFloat(), y1.toFloat()); lineTo(x2.toFloat(), y2.toFloat()) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, max(80L, durationMs)))
            .build()
        val latch = java.util.concurrent.atomic.AtomicBoolean(false)
        val callback = object : GestureResultCallback() {
            override fun onCompleted(g: GestureDescription?) = latch.set(true)
            override fun onCancelled(g: GestureDescription?) = latch.set(false)
        }
        return runCatching {
            dispatchGesture(gesture, callback, mainHandler)
            val deadline = System.currentTimeMillis() + max(400L, durationMs + 250L)
            while (System.currentTimeMillis() < deadline && !latch.get()) Thread.sleep(10)
            latch.get()
        }.getOrDefault(false)
    }

    /** Long-press a single coordinate by holding still for [durationMs]. */
    fun longPressAt(x: Int, y: Int, durationMs: Long): Boolean {
        require(serviceConnected) { "service not connected" }
        if (safeModeEnabled) {
            Log.w(TAG, "longPressAt blocked: safe mode enabled")
            return false
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, max(200L, durationMs)))
            .build()
        val latch = java.util.concurrent.atomic.AtomicBoolean(false)
        val callback = object : GestureResultCallback() {
            override fun onCompleted(g: GestureDescription?) = latch.set(true)
            override fun onCancelled(g: GestureDescription?) = latch.set(false)
        }
        return runCatching {
            dispatchGesture(gesture, callback, mainHandler)
            val deadline = System.currentTimeMillis() + max(500L, durationMs + 300L)
            while (System.currentTimeMillis() < deadline && !latch.get()) Thread.sleep(10)
            latch.get()
        }.getOrDefault(false)
    }

    /** Custom multi-segment gesture path. */
    fun customGesturePath(points: List<Pair<Int, Int>>, totalDurationMs: Long): Boolean {
        require(serviceConnected) { "service not connected" }
        if (safeModeEnabled) {
            Log.w(TAG, "customGesturePath blocked: safe mode enabled")
            return false
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N || points.size < 2) return false
        val path = Path()
        points.forEachIndexed { i, p ->
            if (i == 0) path.moveTo(p.first.toFloat(), p.second.toFloat())
            else path.lineTo(p.first.toFloat(), p.second.toFloat())
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, max(200L, totalDurationMs)))
            .build()
        val latch = java.util.concurrent.atomic.AtomicBoolean(false)
        val callback = object : GestureResultCallback() {
            override fun onCompleted(g: GestureDescription?) = latch.set(true)
            override fun onCancelled(g: GestureDescription?) = latch.set(false)
        }
        return runCatching {
            dispatchGesture(gesture, callback, mainHandler)
            val deadline = System.currentTimeMillis() + max(600L, totalDurationMs + 300L)
            while (System.currentTimeMillis() < deadline && !latch.get()) Thread.sleep(10)
            latch.get()
        }.getOrDefault(false)
    }

    fun scrollForward(): Boolean {
        if (safeModeEnabled) {
            Log.w(TAG, "scrollForward blocked: safe mode enabled")
            return false
        }
        val node = findFirst(rootInActiveWindow) { it.isScrollable } ?: return false
        val ok = node.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
        node.recycle()
        return ok
    }

    fun setText(text: String): Boolean {
        require(serviceConnected) { "service not connected" }
        if (safeModeEnabled) {
            Log.w(TAG, "setText blocked: safe mode enabled")
            return false
        }
        // Try 1: standard ACTION_SET_TEXT on the focused/editable node.
        // Works for all normal Android EditTexts including WeChat/Douyin/Xhs
        // chat inputs and supports Unicode (Chinese/emoji/etc.).
        val focus = findFirst(rootInActiveWindow) { it.isEditable || it.isFocused }
        if (focus != null) {
            val args = Bundle().apply {
                putCharSequence(
                    AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                    text
                )
            }
            val ok = focus.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
            focus.recycle()
            if (ok) return true
        }
        // Try 2: Clipboard + paste fallback.
        // Covers Flutter/RN custom text inputs where the underlying EditText
        // does not accept ACTION_SET_TEXT reliably. We set the clipboard and
        // then dispatch the node-level ACTION_PASTE on the focused node.
        // Note: there is no paste *global action* constant in any SDK
        // (AccessibilityService.GLOBAL_ACTION_PASTE does not exist), so we use
        // AccessibilityNodeInfo.ACTION_PASTE, available since API 18.
        return try {
            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            cm.setPrimaryClip(ClipData.newPlainText("openagent_input", text))
            val node = findFirst(rootInActiveWindow) { it.isFocused || it.isEditable }
            val ok = node?.performAction(AccessibilityNodeInfo.ACTION_PASTE) ?: false
            node?.recycle()
            ok
        } catch (t: Throwable) {
            Log.w(TAG, "clipboard+paste fallback failed", t)
            false
        }
    }

    fun pressBack(): Boolean {
        if (!serviceConnected) return false
        if (safeModeEnabled) {
            Log.w(TAG, "pressBack blocked: safe mode enabled")
            return false
        }
        performGlobalAction(GLOBAL_ACTION_BACK)
        return true
    }
    fun pressHome(): Boolean {
        if (!serviceConnected) return false
        if (safeModeEnabled) {
            Log.w(TAG, "pressHome blocked: safe mode enabled")
            return false
        }
        performGlobalAction(GLOBAL_ACTION_HOME)
        return true
    }
    fun pressRecent(): Boolean {
        if (!serviceConnected) return false
        if (safeModeEnabled) {
            Log.w(TAG, "pressRecent blocked: safe mode enabled")
            return false
        }
        performGlobalAction(GLOBAL_ACTION_RECENTS)
        return true
    }

    fun dumpUiHierarchy(): List<Map<String, Any?>> =
        UiNodeJson.toMap(rootInActiveWindow)

    // ---- Helpers -----------------------------------------------------------

    private inline fun findFirst(
        root: AccessibilityNodeInfo?,
        predicate: (AccessibilityNodeInfo) -> Boolean
    ): AccessibilityNodeInfo? {
        if (root == null) return null
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        val seen = HashSet<AccessibilityNodeInfo>()
        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            if (!seen.add(node)) continue
            val matches = runCatching { predicate(node) }.getOrDefault(false)
            if (matches) return node
            for (i in 0 until min(node.childCount, 500)) {
                val c = node.getChild(i) ?: continue
                queue.add(c)
            }
        }
        return null
    }
}
