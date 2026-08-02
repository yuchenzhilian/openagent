package com.openagent.openagent.automation

import android.graphics.Rect
import android.os.Build
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Serialises an AccessibilityNodeInfo (and its subtree) into a JSON-friendly
 * HashMap that can be passed back to Dart over the MethodChannel.
 *
 * Output schema for each node:
 * {
 *   "text":      "按钮上的文字" | null,
 *   "content_description": "可访问性描述" | null,
 *   "id":        "com.tencent.mm:id/b4k" | null,
 *   "className": "android.widget.Button" | null,
 *   "pkg":       "com.tencent.mm",
 *   "bounds":    [x0, y0, x1, y1],      // screen coordinates (px)
 *   "clickable": true/false,
 *   "scrollable": true/false,
 *   "editable":  true/false,
 *   "checkable": true/false,
 *   "checked":   true/false,
 *   "focused":   true/false,
 *   "children":  [ { node }, ... ]
 * }
 */
object UiNodeJson {

    private const val MAX_DEPTH = 30
    private const val TAG = "UiNodeJson"

    fun toMap(root: AccessibilityNodeInfo?): List<Map<String, Any?>> {
        if (root == null) return emptyList()
        val out = ArrayList<Map<String, Any?>>()
        try {
            collectNodes(root, out, depth = 0)
        } catch (t: Throwable) {
            Log.w(TAG, "Error dumping UI tree", t)
        }
        return out
    }

    private fun collectNodes(
        node: AccessibilityNodeInfo,
        out: ArrayList<Map<String, Any?>>,
        depth: Int
    ) {
        if (depth > MAX_DEPTH) return
        out.add(serialiseOne(node))
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            try {
                collectNodes(child, out, depth + 1)
            } finally {
                child.recycle()
            }
        }
    }

    private fun serialiseOne(n: AccessibilityNodeInfo): Map<String, Any?> {
        val out = HashMap<String, Any?>(16)
        out["text"] = n.text?.toString()
        out["content_description"] = n.contentDescription?.toString()
        out["id"] = n.viewIdResourceName
        out["className"] = n.className?.toString()
        out["pkg"] = n.packageName?.toString()

        val r = Rect()
        n.getBoundsInScreen(r)
        out["bounds"] = listOf(r.left, r.top, r.right, r.bottom)

        out["clickable"] = n.isClickable
        out["scrollable"] = n.isScrollable
        out["editable"] = n.isEditable
        out["checkable"] = n.isCheckable
        out["checked"] = n.isChecked
        out["focused"] = n.isFocused
        out["focusable"] = n.isFocusable
        out["long_clickable"] = n.isLongClickable
        out["selected"] = n.isSelected

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            out["dismissable"] = n.isDismissable
        }
        return out
    }
}
