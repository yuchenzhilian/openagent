package com.openagent.openagent.automation

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.annotation.RequiresApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File

/**
 * Optional bridge to the Shizuku daemon (L2 进阶层).
 *
 * Shizuku lets regular apps execute shell commands with the privilege level of
 * the `shell` user (ADB security boundary — higher than a regular app, lower
 * than root). We use it for:
 *   - `input tap/swipe/text/keyevent` (game control, UI without View nodes).
 *   - `am start -p/…` (launch any installed app by package name).
 *   - `screencap -p` (faster than MediaProjection when available).
 *   - `pm list packages` (list installed apps for the Agent to pick from).
 *
 * When Shizuku is not installed, the user denied permission, or a specific
 * command fails, all methods return a fallback status so the Dart layer can
 * fall back to L1 (Accessibility) or report a useful error.
 *
 * Shizuku docs: https://github.com/RikkaApps/Shizuku/wiki
 * The actual Shizuku SDK dependency is OPTIONAL. This class uses reflection
 * to call `rikka.shizuku.Shizuku` at runtime so the app still compiles & runs
 * on devices without Shizuku SDK linked in.
 *
 * To ENABLE Shizuku SDK properly in a future step, add in app/build.gradle.kts:
 *   implementation("dev.rikka.shizuku:api:13.1.5")
 *   implementation("dev.rikka.shizuku:provider:13.1.5")
 */
object ShizukuShell {

    private const val TAG = "OAShizuku"

    /** Detects whether Shizuku is installed & the app has been authorised. */
    fun isAvailable(context: Context): Boolean {
        return runCatching {
            val cls = Class.forName("rikka.shizuku.Shizuku")
            // Check 1: ping the Binder (requires Shizuku service running)
            val pingBinder = cls.getMethod("pingBinder")
            val alive = pingBinder.invoke(null) as? Boolean ?: false
            if (!alive) return@runCatching false
            // Check 2: do we have the runtime permission to call newProcess?
            val checkSelfPerm = cls.getMethod("checkSelfPermission", String::class.java)
            val perm = checkSelfPerm.invoke(null, "moe.shizuku.manager.permission.API_V23") as? Int
            val granted = perm == 0 // PackageManager.PERMISSION_GRANTED
            if (!granted) return@runCatching false
            // Optional check 3: confirm effective uid is AID_SHELL (2000) so
            // commands truly run with shell-user privilege (not regular app).
            runCatching {
                val getUid = cls.getMethod("getUid")
                val uid = getUid.invoke(null) as? Int ?: -1
                if (uid != -1) Log.v(TAG, "Shizuku available: uid=$uid")
            }
            true
        }.getOrDefault(false)
    }

    /** Execute a shell command.
     *
     * Strategy: when Shizuku is available we call `rikka.shizuku.Shizuku.newProcess`
     * via reflection — this returns a standard `java.lang.Process` running with
     * AID_SHELL privilege (higher than a regular app). If unavailable we fall
     * back to `Runtime.exec` (regular-app privilege). Both paths feed into the
     * same stdout/stderr/exitCode pipeline. */
    fun run(cmd: String): CommandResult {
        return try {
            val cmdArr = arrayOf("sh", "-c", cmd)
            val process: Process = runCatching {
                val cls = Class.forName("rikka.shizuku.Shizuku")
                val checkPerm = cls.getMethod("checkSelfPermission", String::class.java)
                val perm = checkPerm.invoke(null, "moe.shizuku.manager.permission.API_V23") as? Int
                if (perm == 0) {
                    @Suppress("UNCHECKED_CAST")
                    val m = cls.getMethod(
                        "newProcess",
                        Array<String>::class.java,
                        Array<String>::class.java,
                        File::class.java
                    )
                    m.invoke(null, cmdArr, null, null) as? Process
                        ?: error("Shizuku.newProcess returned null")
                } else null
            }.getOrNull() ?: Runtime.getRuntime().exec(cmdArr)

            val stdout = process.inputStream.bufferedReader().use(BufferedReader::readText)
            val stderr = process.errorStream.bufferedReader().use(BufferedReader::readText)
            val rc = process.waitFor()
            Log.d(TAG, "shell '$cmd' exited $rc; stderr=${stderr.take(160)}")
            CommandResult(rc, stdout, stderr)
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to run '$cmd'", t)
            CommandResult(-1, "", t.message ?: "unknown error")
        }
    }

    data class CommandResult(val exitCode: Int, val stdout: String, val stderr: String) {
        val ok: Boolean get() = exitCode == 0
    }

    // --- Convenience wrappers used by AutomationBridge ----------------------

    fun inputTap(x: Int, y: Int): CommandResult = run("input tap $x $y")
    fun inputSwipe(x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Long): CommandResult =
        run("input swipe $x1 $y1 $x2 $y2 $durationMs")
    fun inputText(text: String): CommandResult {
        // `input text` only works with %s-escaped strings. URL-encode spaces to %s
        // because `adb shell input text` treats "%s" as space literal.
        val escaped = text.replace(" ", "%s")
        return run("input text \"$escaped\"")
    }
    fun inputKeyEvent(code: Int): CommandResult = run("input keyevent $code")

    fun openApp(context: Context, packageName: String): Boolean {
        return runCatching {
            val launch = context.packageManager.getLaunchIntentForPackage(packageName)
            if (launch != null) {
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(launch)
                return true
            }
            // Fallback: try am start
            val r = run("am start -p $packageName")
            r.ok
        }.getOrDefault(false)
    }

    fun listPackages(): List<String> {
        val r = run("pm list packages")
        if (!r.ok) return emptyList()
        return r.stdout.lineSequence()
            .map { it.trim().removePrefix("package:") }
            .filter { it.isNotBlank() }
            .toList()
    }

    fun screenResolution(): Pair<Int, Int>? {
        val r = run("dumpsys window displays | grep init=")
        if (!r.ok) return null
        val m = Regex("init=(\\d+)x(\\d+)").find(r.stdout) ?: return null
        return m.groupValues[1].toInt() to m.groupValues[2].toInt()
    }

    fun screencap(outFile: File): Boolean {
        val r = run("screencap -p '${outFile.absolutePath}'")
        return r.ok && outFile.exists() && outFile.length() > 4096
    }
}
