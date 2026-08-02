package com.openagent.openagent.automation

import android.Manifest
import android.app.Activity
import android.app.AppOpsManager
import android.app.WallpaperManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.util.HashSet
import kotlin.math.maxOf

/**
 * MethodChannel bridge between Dart (Agent runtime) and Android automation
 * services (L1 Accessibility + L2 Shizuku).
 *
 * Channel name: com.openagent.automation
 *
 * Method list (callable from Dart)
 * --------------------------------
 *  is_accessibility_enabled         → bool   (check L1 is connected)
 *  open_accessibility_settings      → void   (deep-link to Settings)
 *  is_shizuku_available             → bool
 *  open_shizuku_app                 → bool
 *  android_open_app(package_name)   → bool
 *  android_click_by_text(text, exact?) → bool
 *  android_click_by_id(view_id)     → bool
 *  android_click_coords(x, y)       → bool
 *  android_swipe(x1,y1,x2,y2,ms?)   → bool
 *  android_scroll_forward()         → bool
 *  android_input_text(text)         → bool
 *  android_press_key(key:home/back/recent/vol_up/vol_down/power/enter/del) → bool
 *  android_dump_ui                  → List<Map> (JSON serialised UI tree)
 *  android_list_packages            → List<String>  (package names installed)
 *  android_screen_resolution        → [w, h] | null
 *  android_screenshot               → String?  (absolute file path to PNG, app cache)
 *  android_screenshot_ocr           → List<Map>? (TODO placeholder — Omni handles OCR via vision)
 *  android_install_apk(apk_path)    → bool
 */
class AutomationChannel(private val context: Context) {

    companion object {
        private const val TAG = "OAAutomationBridge"
        private const val CHANNEL = "com.openagent.automation"

        private const val KEYCODE_HOME = 3
        private const val KEYCODE_BACK = 4
        private const val KEYCODE_VOLUME_UP = 24
        private const val KEYCODE_VOLUME_DOWN = 25
        private const val KEYCODE_POWER = 26
        private const val KEYCODE_ENTER = 66
        private const val KEYCODE_DEL = 67
        private const val KEYCODE_APP_SWITCH = 187
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private lateinit var channel: MethodChannel

    fun attach(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        channel = MethodChannel(messenger, CHANNEL)
        channel.setMethodCallHandler { call, result -> handle(call, result) }
    }

    fun detach() {
        if (::channel.isInitialized) channel.setMethodCallHandler(null)
    }

    private fun handle(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        scope.launch {
            val answer = runCatching { handleSuspend(call) }
                .getOrElse { t ->
                    Log.e(TAG, "method ${call.method} failed", t)
                    result.error(t.javaClass.simpleName, t.message, null)
                    return@launch
                }
            result.success(answer)
        }
    }

    private suspend fun handleSuspend(call: io.flutter.plugin.common.MethodCall): Any? =
        withContext(Dispatchers.Default) {
            when (call.method) {
                "is_accessibility_enabled" -> OpenAgentAccessibilityService.isServiceConnected()

                "open_accessibility_settings" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                    true
                }

                "is_shizuku_available" -> ShizukuShell.isAvailable(context)

                "open_shizuku_app" -> {
                    val r = runCatching {
                        val i = context.packageManager.getLaunchIntentForPackage("moe.shizuku.privileged.api")
                        if (i != null) {
                            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(i)
                            true
                        } else {
                            val uri = Uri.parse("market://details?id=moe.shizuku.privileged.api")
                            context.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            false
                        }
                    }
                    r.getOrDefault(false)
                }

                "open_usage_access_settings" -> {
                    // Some custom ROMs redirect this Intent, so we try the explicit
                    // package-specific Intent first and fall back to the generic one.
                    runCatching {
                        val pkgUri = Uri.fromParts("package", context.packageName, null)
                        val i = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS, pkgUri)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(i)
                    }.recoverCatching {
                        val i = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(i)
                    }
                    true
                }

                "android_open_app" -> {
                    val pkg = call.argument<String>("package_name")
                        ?: return@withContext error("missing package_name")
                    val shizukuOk = ShizukuShell.isAvailable(context)
                    // Prefer the official LaunchIntent (works always); fall back
                    // to pm/am for any package the LaunchIntent doesn't find.
                    var ok = ShizukuShell.openApp(context, pkg)
                    if (!ok && shizukuOk) ok = ShizukuShell.run("am start -p $pkg").ok
                    ok
                }

                "android_click_by_text" -> {
                    val text = call.argument<String>("text") ?: return@withContext false
                    val exact = call.argument<Boolean>("exact") ?: true
                    onMainSync {
                        OpenAgentAccessibilityService.requireInstance()?.clickByText(text, exact) == true
                    }
                }

                "android_click_by_id" -> {
                    val id = call.argument<String>("view_id") ?: return@withContext false
                    onMainSync {
                        OpenAgentAccessibilityService.requireInstance()?.clickById(id) == true
                    }
                }

                "android_click_coords" -> {
                    val x = call.argument<Int>("x") ?: return@withContext false
                    val y = call.argument<Int>("y") ?: return@withContext false
                    val viaAcc = onMainSync {
                        OpenAgentAccessibilityService.requireInstance()?.clickAtCoords(x, y) == true
                    }
                    viaAcc || ShizukuShell.inputTap(x, y).ok
                }

                "android_swipe" -> {
                    val x1 = call.argument<Int>("x1") ?: return@withContext false
                    val y1 = call.argument<Int>("y1") ?: return@withContext false
                    val x2 = call.argument<Int>("x2") ?: return@withContext false
                    val y2 = call.argument<Int>("y2") ?: return@withContext false
                    val dur = call.argument<Int>("duration_ms") ?: 300
                    val viaAcc = onMainSync {
                        OpenAgentAccessibilityService.requireInstance()
                            ?.swipe(x1, y1, x2, y2, dur.toLong()) == true
                    }
                    viaAcc || ShizukuShell.inputSwipe(x1, y1, x2, y2, dur.toLong()).ok
                }

                "android_scroll_forward" -> onMainSync {
                    OpenAgentAccessibilityService.requireInstance()?.scrollForward() == true
                }

                "android_input_text" -> {
                    val text = call.argument<String>("text") ?: return@withContext false
                    val viaAcc = onMainSync {
                        OpenAgentAccessibilityService.requireInstance()?.setText(text) == true
                    }
                    viaAcc || ShizukuShell.inputText(text).ok
                }

                "android_press_key" -> {
                    val k = (call.argument<String>("key") ?: return@withContext false).lowercase()
                    val code = when (k) {
                        "home" -> KEYCODE_HOME
                        "back" -> KEYCODE_BACK
                        "recent", "app_switch" -> KEYCODE_APP_SWITCH
                        "volume_up", "vol_up" -> KEYCODE_VOLUME_UP
                        "volume_down", "vol_down" -> KEYCODE_VOLUME_DOWN
                        "power" -> KEYCODE_POWER
                        "enter" -> KEYCODE_ENTER
                        "del", "delete" -> KEYCODE_DEL
                        else -> -1
                    }
                    if (code < 0) return@withContext false
                    // Prefer L1 for home/back/recent (no shell permission needed)
                    when (code) {
                        KEYCODE_BACK -> if (onMainSync { OpenAgentAccessibilityService.requireInstance()?.pressBack() == true }) return@withContext true
                        KEYCODE_HOME -> if (onMainSync { OpenAgentAccessibilityService.requireInstance()?.pressHome() == true }) return@withContext true
                        KEYCODE_APP_SWITCH -> if (onMainSync { OpenAgentAccessibilityService.requireInstance()?.pressRecent() == true }) return@withContext true
                    }
                    ShizukuShell.inputKeyEvent(code).ok
                }

                "android_dump_ui" -> onMainSync {
                    OpenAgentAccessibilityService.requireInstance()?.dumpUiHierarchy()
                        ?: emptyList<Map<String, Any?>>()
                }

                "android_list_packages" -> ShizukuShell.listPackages()

                "android_screen_resolution" -> ShizukuShell.screenResolution()?.let { listOf(it.first, it.second) }

                "android_screenshot" -> {
                    val out = File(context.cacheDir, "oa_screenshot_${System.currentTimeMillis()}.png")
                    // Prefer Shizuku screencap (fast, no permission grant flow)
                    if (ShizukuShell.screencap(out)) return@withContext out.absolutePath
                    // Fallback: MediaProjection ScreenshotManager (requires user to grant)
                    val act = context as? Activity ?: return@withContext null
                    ScreenshotManager.takeScreenshot(act, out)
                    if (out.exists() && out.length() > 4096) out.absolutePath else null
                }

                "android_screenshot_ocr" -> {
                    // NOTE: OCR is handled in the Dart side by sending the
                    // screenshot PNG straight to the Omni multimodal model via
                    // MnnOmniSession.chatStream, which has its own vision encoder.
                    // Returning null here leaves the Agent to use Omni + screenshot.
                    null
                }

                "android_install_apk" -> {
                    val apk = call.argument<String>("apk_path") ?: return@withContext false
                    val r = ShizukuShell.run("pm install -r '$apk'")
                    if (r.ok) return@withContext true
                    // Regular-user intent install (requires user confirmation)
                    val uri = Uri.fromFile(File(apk))
                    val i = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    context.startActivity(i)
                    false
                }

                // ---- Aggregate permission/status used by Dart service layer ----
                "android_get_permission_status" -> mapOf<String, Any?>(
                    "accessibility_enabled" to OpenAgentAccessibilityService.isServiceConnected(),
                    "shizuku_granted" to ShizukuShell.isAvailable(context),
                    "screenshot_granted" to ScreenshotManager.isReady(),
                    "usage_stats_granted" to hasUsageStatsPermission(context),
                )

                // ---- Top foreground app detection (for Agent to "know where it is") ----
                "android_top_app" -> {
                    val info = getForegroundApp(context)
                    if (info != null) mapOf<String, Any?>(
                        "package" to info.first,
                        "activity" to info.second,
                    ) else emptyMap<String, Any?>()
                }

                // ---- Raw shell via Shizuku (Agent L2 fallback) ----
                "android_gshell" -> {
                    val cmd = call.argument<String>("command") ?: return@withContext mapOf<String, Any?>()
                    val r = ShizukuShell.run(cmd)
                    mapOf<String, Any?>(
                        "exit_code" to r.exitCode,
                        "stdout" to r.stdout,
                        "stderr" to r.stderr,
                        "ok" to r.ok,
                    )
                }

                // ---- H12: Native implementations for new open primitives ----
                "android_long_press" -> {
                    val x = call.argument<Int>("x") ?: return@withContext false
                    val y = call.argument<Int>("y") ?: return@withContext false
                    val dur = (call.argument<Int>("duration_ms") ?: 800).toLong()
                    val viaAcc = onMainSync {
                        OpenAgentAccessibilityService.requireInstance()
                            ?.longPressAt(x, y, dur) == true
                    }
                    viaAcc || ShizukuShell.inputSwipe(x, y, x, y, dur).ok
                }

                "android_custom_gesture" -> {
                    val raw = call.argument<List<Map<String, Int>>>("points") ?: emptyList()
                    val dur = (call.argument<Int>("duration_ms") ?: 500).toLong()
                    val pts: List<Pair<Int, Int>> = raw.mapNotNull { m ->
                        val x = m["x"]; val y = m["y"]
                        if (x != null && y != null) x to y else null
                    }
                    if (pts.size < 2) return@withContext false
                    val viaAcc = onMainSync {
                        OpenAgentAccessibilityService.requireInstance()
                            ?.customGesturePath(pts, dur) == true
                    }
                    viaAcc || run {
                        // Shell fallback: segment-by-segment input swipe
                        val seg = maxOf(50L, dur / (pts.size - 1))
                        var lastOk = true
                        for (i in 0 until pts.size - 1) {
                            val r = ShizukuShell.inputSwipe(
                                pts[i].first, pts[i].second,
                                pts[i + 1].first, pts[i + 1].second, seg
                            )
                            if (!r.ok) lastOk = false
                        }
                        lastOk
                    }
                }

                "android_get_clipboard" -> {
                    runCatching {
                        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                        val clip = cm.primaryClip
                        if (clip == null || clip.itemCount == 0) return@runCatching ""
                        val first = clip.getItemAt(0)
                        first.text?.toString() ?: first.coerceToText(context)?.toString() ?: ""
                    }.getOrDefault("")
                }

                "android_set_clipboard" -> {
                    val text = call.argument<String>("text") ?: return@withContext false
                    runCatching {
                        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                        cm.setPrimaryClip(android.content.ClipData.newPlainText("openagent", text))
                        true
                    }.getOrDefault(false)
                }

                "android_get_notifications" -> {
                    val limit = call.argument<Int>("limit") ?: 30
                    val sb = StringBuilder()
                    try {
                        // activeNotifications added in API 23 (M). May throw
                        // SecurityException if NotificationListener permission was
                        // not granted by the user. That's caught here; Dart layer
                        // then falls back to shell dumpsys notification.
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                            val active = runCatching { nm.activeNotifications }.getOrNull().orEmpty()
                            active.take(limit).forEachIndexed { i, sbn ->
                                val n = sbn.notification
                                val extras: android.os.Bundle? = n.extras
                                val title = extras?.getCharSequence(android.app.Notification.EXTRA_TITLE)
                                    ?: extras?.get(android.app.Notification.EXTRA_TITLE_BIG)
                                    ?: ""
                                val text = extras?.getCharSequence(android.app.Notification.EXTRA_TEXT)
                                    ?: extras?.getCharSequence("android.textLines")
                                        ?.let { if (it is Array<*>) it.joinToString("\n") else it.toString() }
                                    ?: ""
                                sb.appendLine("[$i] pkg=${sbn.packageName}  time=${android.text.format.DateFormat.format("MM-dd HH:mm:ss", sbn.postTime)}")
                                if (title.isNotBlank()) sb.appendLine("    title: $title")
                                if (text.isNotBlank()) sb.appendLine("    text:  $text")
                                sb.appendLine("    ongoing=${n.flags and android.app.Notification.FLAG_ONGOING_EVENT != 0}  clearable=${sbn.isClearable}  channel=${n.channelId ?: ""}")
                                sbn.tag?.let { sb.appendLine("    tag=$it") }
                            }
                        }
                        // Also merge cached NotificationListenerService snapshots if
                        // available (deduplicate by pkg+tag+id).
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val cached = OpenAgentNotificationListener.dumpRecent(limit.coerceAtLeast(10))
                            val seen = HashSet<String>()
                            cached.forEach { snap ->
                                val key = "${snap.pkg}|${snap.tag ?: ""}|${snap.id}"
                                if (seen.add(key)) sb.append(snap.renderLine(-1))
                            }
                        }
                    } catch (t: Throwable) {
                        sb.append("(NotificationListener 未授予或不可用, err=${t.javaClass.simpleName})")
                    }
                    sb.toString()
                }

                // ---- H16: Runtime permission checking + requesting ----
                "android_check_permissions" -> {
                    val raw = call.argument<List<String>>("permissions").orEmpty()
                    // If empty list, default to all dangerous permissions we've
                    // declared in the manifest (Manifest.permission.* that are
                    // known runtime permissions at SDK level).
                    val targets = raw.ifEmpty {
                        listOf(
                            Manifest.permission.POST_NOTIFICATIONS,
                            Manifest.permission.RECORD_AUDIO,
                            Manifest.permission.CAMERA,
                            Manifest.permission.READ_CONTACTS,
                            Manifest.permission.WRITE_CONTACTS,
                            Manifest.permission.READ_SMS,
                            Manifest.permission.SEND_SMS,
                            Manifest.permission.READ_CALL_LOG,
                            Manifest.permission.WRITE_CALL_LOG,
                            Manifest.permission.CALL_PHONE,
                            Manifest.permission.READ_PHONE_STATE,
                            Manifest.permission.READ_PHONE_NUMBERS,
                            Manifest.permission.ACCESS_FINE_LOCATION,
                            Manifest.permission.ACCESS_COARSE_LOCATION,
                            Manifest.permission.ACCESS_BACKGROUND_LOCATION,
                            Manifest.permission.READ_MEDIA_IMAGES,
                            Manifest.permission.READ_MEDIA_VIDEO,
                            Manifest.permission.READ_MEDIA_AUDIO,
                            Manifest.permission.BODY_SENSORS,
                            Manifest.permission.ACTIVITY_RECOGNITION,
                            Manifest.permission.BLUETOOTH_SCAN,
                            Manifest.permission.BLUETOOTH_CONNECT,
                        )
                    }
                    val sb = StringBuilder()
                    for (perm in targets) {
                        // SDK filter: don't report PERMISSION_DENIED for permissions
                        // that didn't exist at this phone's SDK level.
                        val minSdk = minSdkForPermission(perm)
                        if (Build.VERSION.SDK_INT < minSdk) {
                            sb.appendLine("$perm = NOT_APPLICABLE (SDK min=$minSdk, current=${Build.VERSION.SDK_INT})")
                            continue
                        }
                        val grant = ContextCompat.checkSelfPermission(context, perm)
                        val state = if (grant == PackageManager.PERMISSION_GRANTED) "GRANTED" else "DENIED"
                        sb.appendLine("$perm = $state (checkSelfPermission=$grant)")
                    }
                    sb.toString()
                }

                "android_request_permissions" -> {
                    val perms = call.argument<List<String>>("permissions").orEmpty()
                        .filter { it.isNotBlank() }
                    if (perms.isEmpty()) return@withContext "permissions 数组为空，什么也没做"
                    // Only Activity can call requestPermissions (the user-facing
                    // permission dialog). If Dart code is calling from background
                    // or our context isn't an Activity, we fall back to the
                    // APPLICATION_DETAILS_SETTINGS intent on the Dart side.
                    val act = context as? Activity
                    if (act == null) {
                        return@withContext "Context 非前台 Activity，不能弹权限对话框。已交由 Dart 层跳应用详情页。"
                    }
                    // Filter out permissions already granted.
                    val needed = perms.filter {
                        ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED
                    }
                    if (needed.isEmpty()) {
                        return@withContext "所有权限已授予（${perms.size} 项），无需再弹对话框。"
                    }
                    // Use requestPermissions (no result callback in this fire-and-
                    // forget wrapper; the Dart layer polls check_permissions after
                    // the user taps Allow/Deny).
                    val code = (System.currentTimeMillis() and 0xFFFF).toInt()
                    runCatching {
                        ActivityCompat.requestPermissions(act, needed.toTypedArray(), code)
                    }
                    val sb = StringBuilder()
                    sb.appendLine("已下发 requestPermissions 对话框 (requestCode=$code)")
                    sb.appendLine("待授权 (${needed.size} 项):")
                    needed.forEach { sb.appendLine("  - $it") }
                    sb.appendLine("（用户点允许/拒绝后，再次调用 android_check_permissions 可查到最新状态）")
                    sb.toString()
                }

                // ---- H17: Build info (hardware/SDK fields), wallpaper ----
                "android_get_build_info" -> {
                    val sb = StringBuilder()
                    sb.appendLine("Build.MODEL        = ${Build.MODEL}")
                    sb.appendLine("Build.BRAND        = ${Build.BRAND}")
                    sb.appendLine("Build.MANUFACTURER = ${Build.MANUFACTURER}")
                    sb.appendLine("Build.DEVICE       = ${Build.DEVICE}")
                    sb.appendLine("Build.PRODUCT      = ${Build.PRODUCT}")
                    sb.appendLine("Build.HARDWARE     = ${Build.HARDWARE}")
                    sb.appendLine("Build.BOARD        = ${Build.BOARD}")
                    sb.appendLine("Build.SOC_MODEL    = ${if (Build.VERSION.SDK_INT >= 31) Build.SOC_MODEL else "(SDK<31)"}")
                    sb.appendLine("Build.SOC_MANUFACTURER = ${if (Build.VERSION.SDK_INT >= 31) Build.SOC_MANUFACTURER else "(SDK<31)"}")
                    sb.appendLine("Build.VERSION.SDK_INT   = ${Build.VERSION.SDK_INT}")
                    sb.appendLine("Build.VERSION.RELEASE   = ${Build.VERSION.RELEASE}")
                    sb.appendLine("Build.VERSION.CODENAME  = ${Build.VERSION.CODENAME}")
                    sb.appendLine("Build.VERSION.INCREMENTAL = ${Build.VERSION.INCREMENTAL}")
                    sb.appendLine("Build.VERSION.BASE_OS   = ${if (Build.VERSION.SDK_INT >= 23) Build.VERSION.BASE_OS else "(SDK<23)"}")
                    sb.appendLine("Build.VERSION.SECURITY_PATCH = ${if (Build.VERSION.SDK_INT >= 23) Build.VERSION.SECURITY_PATCH else "(SDK<23)"}")
                    sb.appendLine("Build.FINGERPRINT  = ${Build.FINGERPRINT}")
                    sb.appendLine("Build.TYPE         = ${Build.TYPE}")
                    sb.appendLine("Build.FLAVOR       = ${Build.FLAVOR}")
                    sb.appendLine("Build.TAGS         = ${Build.TAGS}")
                    sb.appendLine("Build.ID           = ${Build.ID}")
                    sb.appendLine("Build.DISPLAY      = ${Build.DISPLAY}")
                    sb.appendLine("Build.USER         = ${Build.USER}")
                    sb.appendLine("Build.HOST         = ${Build.HOST}")
                    sb.appendLine("Build.TIME         = ${Build.TIME} (${android.text.format.DateFormat.format("yyyy-MM-dd HH:mm:ss", Build.TIME)})")
                    sb.appendLine("Build.RADIO        = ${Build.getRadioVersion() ?: "(unknown)"}")
                    sb.appendLine("Build.SERIAL (masked) = ${runCatching { Build.SERIAL.take(4) + "***" + Build.SERIAL.takeLast(2) }.getOrDefault("(hidden)")}")
                    sb.appendLine("SUPPORTED_ABIS     = ${Build.SUPPORTED_ABIS.joinToString(", ")}")
                    sb.appendLine("SUPPORTED_32_BIT_ABIS = ${Build.SUPPORTED_32_BIT_ABIS.joinToString(", ")}")
                    sb.appendLine("SUPPORTED_64_BIT_ABIS = ${Build.SUPPORTED_64_BIT_ABIS.joinToString(", ")}")
                    if (Build.VERSION.SDK_INT >= 23) {
                        sb.appendLine("Build.VERSION.PREVIEW_SDK_INT = ${Build.VERSION.PREVIEW_SDK_INT}")
                    }
                    sb.toString()
                }

                "android_set_wallpaper" -> {
                    val path = call.argument<String>("path") ?: return@withContext "FAIL: missing path"
                    val which = call.argument<String>("which") ?: "both"
                    val file = File(path)
                    if (!file.exists() || file.length() < 1024) {
                        return@withContext "FAIL: file too small or not found: $path (size=${file.length()})"
                    }
                    val bmp = runCatching { BitmapFactory.decodeFile(path) }.getOrNull()
                    if (bmp == null) {
                        return@withContext "FAIL: BitmapFactory.decodeFile 返回 null，图片可能损坏: $path"
                    }
                    var setOk = 0
                    val wm = runCatching { WallpaperManager.getInstance(context) }.getOrNull()
                    if (wm != null) {
                        val targetHome = which == "home" || which == "both"
                        val targetLock = which == "lock" || which == "both"
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            if (targetHome) {
                                runCatching {
                                    wm.setBitmap(bmp, null, true, WallpaperManager.FLAG_SYSTEM)
                                }.onSuccess { setOk = setOk or 1 }
                            }
                            if (targetLock) {
                                runCatching {
                                    wm.setBitmap(bmp, null, true, WallpaperManager.FLAG_LOCK)
                                }.onSuccess { setOk = setOk or 2 }
                            }
                        } else {
                            // < N: only supports setting the system (home) wallpaper.
                            if (targetHome) {
                                runCatching { wm.setBitmap(bmp) }.onSuccess { setOk = setOk or 1 }
                            }
                        }
                    }
                    if (setOk == 0) {
                        return@withContext "FAIL: WallpaperManager 设置失败 (SDK=${Build.VERSION.SDK_INT} which=$which)，交给 Dart 层 fallback 打开系统壁纸裁剪面板。"
                    }
                    val where = when (setOk) {
                        1 -> "仅桌面"
                        2 -> "仅锁屏"
                        3 -> "桌面 + 锁屏"
                        else -> "(未知)"
                    }
                    "OK: 已设置壁纸 ($where) — ${file.name} (${file.length()} bytes, ${bmp.width}x${bmp.height})"
                }

                else -> throw IllegalArgumentException("Unknown method: ${call.method}")
            }
        }

    private suspend fun <T> onMainSync(block: () -> T): T = withContext(Dispatchers.Main) { block() }

    // ---- Helpers -----------------------------------------------------------

    private fun hasUsageStatsPermission(context: Context): Boolean =
        runCatching {
            val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(), context.packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(), context.packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        }.getOrDefault(false)

    /** Returns the current top activity (package to class name) or null. */
    private fun getForegroundApp(context: Context): Pair<String, String>? {
        // 1) Best effort: UsageStatsManager if we have the permission.
        if (hasUsageStatsPermission(context)) {
            runCatching {
                val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                val now = System.currentTimeMillis()
                val events = usm.queryEvents(now - 60_000L, now)
                val ev = UsageEvents.Event()
                var lastPkg: String? = null
                var lastCls: String? = null
                while (events.hasNextEvent()) {
                    events.getNextEvent(ev)
                    if (ev.eventType == UsageEvents.Event.ACTIVITY_RESUMED
                        || ev.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND
                    ) {
                        lastPkg = ev.packageName
                        lastCls = ev.className
                    }
                }
                if (lastPkg != null) return lastPkg to (lastCls ?: "")
            }
        }
        // 2) Fallback: dump activity top via shell (works if user has Shizuku).
        val r = ShizukuShell.run("dumpsys activity activities | grep -E 'mResumedActivity|topResumedActivity' | head -1")
        if (r.ok) {
            val m = Regex("""([a-zA-Z0-9_.]+)/([a-zA-Z0-9_.$]+)""").find(r.stdout)
            if (m != null) return m.groupValues[1] to m.groupValues[2]
        }
        return null
    }

    /** Minimum SDK level at which each runtime permission was introduced. */
    private fun minSdkForPermission(perm: String): Int = when (perm) {
        Manifest.permission.POST_NOTIFICATIONS -> Build.VERSION_CODES.TIRAMISU // 33
        Manifest.permission.READ_MEDIA_IMAGES,
        Manifest.permission.READ_MEDIA_VIDEO,
        Manifest.permission.READ_MEDIA_AUDIO -> Build.VERSION_CODES.TIRAMISU // 33
        Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED -> Build.VERSION_CODES.UPSIDE_DOWN_CAKE // 34
        Manifest.permission.BLUETOOTH_SCAN,
        Manifest.permission.BLUETOOTH_CONNECT -> Build.VERSION_CODES.S // 31
        Manifest.permission.ACCESS_BACKGROUND_LOCATION -> Build.VERSION_CODES.Q // 29
        Manifest.permission.ACTIVITY_RECOGNITION -> Build.VERSION_CODES.Q // 29
        Manifest.permission.BODY_SENSORS -> Build.VERSION_CODES.KITKAT_WATCH // 20
        Manifest.permission.ANSWER_PHONE_CALLS -> Build.VERSION_CODES.O // 26
        Manifest.permission.READ_PHONE_NUMBERS -> Build.VERSION_CODES.O // 26
        else -> Build.VERSION_CODES.BASE // 1 (old legacy permissions)
    }
}
