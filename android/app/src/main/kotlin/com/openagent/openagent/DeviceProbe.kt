package com.openagent.openagent

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File

/**
 * MethodChannel bridge for real device hardware probing.
 *
 * Channel name: com.openagent.openagent/device_probe
 *
 * Methods (callable from Dart):
 *  probe -> Map: comprehensive device snapshot (memory, cpu, gpu, battery, thermal)
 */
class DeviceProbe(private val context: Context) {

    companion object {
        private const val TAG = "OADeviceProbe"
        private const val CHANNEL = "com.openagent.openagent/device_probe"
    }

    private lateinit var channel: MethodChannel

    fun attach(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        channel = MethodChannel(messenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "probe" -> result.success(probe().toString())
                else -> result.notImplemented()
            }
        }
    }

    fun detach() {
        if (::channel.isInitialized) channel.setMethodCallHandler(null)
    }

    /**
     * Collect a JSON object with all device metrics needed for adaptive
     * inference scheduling and backend selection.
     */
    private fun probe(): JSONObject {
        val json = JSONObject()
        try {
            // ---- Memory ----
            val actManager =
                context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memInfo = ActivityManager.MemoryInfo()
            actManager.getMemoryInfo(memInfo)
            json.put("total_memory_mb", memInfo.totalMem / (1024 * 1024))
            json.put("available_memory_mb", memInfo.availMem / (1024 * 1024))
            json.put("low_memory", memInfo.lowMemory)

            // ---- CPU ----
            val cpuInfo = probeCpu()
            json.put("cpu_core_count", cpuInfo.first)
            json.put("cpu_big_core_count", cpuInfo.second)
            json.put("cpu_max_freq_mhz", cpuInfo.third)

            // ---- GPU ----
            val gpuInfo = probeGpu()
            json.put("gpu_vendor", gpuInfo.first)
            json.put("gpu_model", gpuInfo.second)

            // ---- Battery ----
            val battery = android.content.IntentFilter(
                android.content.Intent.ACTION_BATTERY_CHANGED
            )
            val batteryIntent = context.registerReceiver(null, battery)
            val level = batteryIntent?.getIntExtra(
                android.os.BatteryManager.EXTRA_LEVEL, -1
            ) ?: -1
            val scale = batteryIntent?.getIntExtra(
                android.os.BatteryManager.EXTRA_SCALE, 100
            ) ?: 100
            val status = batteryIntent?.getIntExtra(
                android.os.BatteryManager.EXTRA_STATUS, -1
            ) ?: -1
            val batteryPct = if (scale > 0) (level * 100) / scale else -1
            val isCharging = status == android.os.BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == android.os.BatteryManager.BATTERY_STATUS_FULL
            json.put("battery_percent", batteryPct)
            json.put("is_charging", isCharging)

            // ---- Thermal ----
            val powerManager =
                context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            val thermalLevel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                powerManager?.currentThermalStatus
                    ?: PowerManager.THERMAL_STATUS_NONE
            } else {
                PowerManager.THERMAL_STATUS_NONE
            }
            json.put("thermal_status", thermalLevel)

            val tempCelsius = readCpuTemperature()
            json.put("temperature_celsius", tempCelsius)

            // ---- Android version ----
            json.put("sdk_int", Build.VERSION.SDK_INT)
            json.put("abi", Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown")

        } catch (e: Exception) {
            Log.e(TAG, "probe failed", e)
        }
        return json
    }

    /**
     * Probe CPU core count, big core count (by frequency), and max frequency.
     * Returns (totalCores, bigCores, maxFreqMhz).
     */
    private fun probeCpu(): Triple<Int, Int, Int> {
        var totalCores = 1
        var bigCores = 1
        var maxFreqMhz = 0

        try {
            // Count online CPU cores via /sys/devices/system/cpu/
            val cpuDir = File("/sys/devices/system/cpu/")
            val cpuDirs = cpuDir.listFiles { f ->
                f.isDirectory && f.name.matches(Regex("cpu\\d+"))
            } ?: emptyArray()
            totalCores = cpuDirs.size.coerceAtLeast(1)

            // Read max frequencies to distinguish big vs small cores
            val freqs = mutableListOf<Int>()
            for (i in 0 until totalCores) {
                val freqFile = File("/sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq")
                if (freqFile.exists()) {
                    val freqKhz = freqFile.readText().trim().toIntOrNull() ?: 0
                    val freqMhz = freqKhz / 1000
                    freqs.add(freqMhz)
                    if (freqMhz > maxFreqMhz) maxFreqMhz = freqMhz
                }
            }

            // Big cores = cores whose max freq is within 80% of the highest freq
            if (freqs.isNotEmpty()) {
                val threshold = maxFreqMhz * 0.8
                bigCores = freqs.count { it >= threshold }.coerceAtLeast(1)
            }
        } catch (e: Exception) {
            Log.w(TAG, "CPU probe failed, using defaults", e)
        }

        return Triple(totalCores, bigCores, maxFreqMhz)
    }

    /**
     * Probe GPU vendor and model. On Android we check for Adreno (Qualcomm)
     * or Mali (ARM) GPU sysfs entries, and fall back to OpenGL strings.
     */
    private fun probeGpu(): Pair<String, String> {
        var vendor = "unknown"
        var model = "unknown"

        try {
            // Adreno GPU: /sys/class/kgsl/kgsl-3d0/
            val adrenoDev = File("/sys/class/kgsl/kgsl-3d0/gpuclk")
            if (adrenoDev.exists()) {
                vendor = "adreno"
                // Try to read GPU model from /sys/class/kgsl/kgsl-3d0/gpu_model
                val modelFile = File("/sys/class/kgsl/kgsl-3d0/gpu_model")
                if (modelFile.exists()) {
                    model = modelFile.readText().trim()
                } else {
                    model = "adreno"
                }
                return Pair(vendor, model)
            }

            // Mali GPU: /sys/class/devfreq/mali/
            val maliDev = File("/sys/class/devfreq/")
            if (maliDev.exists()) {
                val maliDirs = maliDev.listFiles { f ->
                    f.isDirectory && f.name.contains("mali", ignoreCase = true)
                }
                if (!maliDirs.isNullOrEmpty()) {
                    vendor = "mali"
                    model = "mali"
                    return Pair(vendor, model)
                }
            }

            // Fallback: check ro.hardware.egl build property
            val eglProp = readSystemProperty("ro.hardware.egl")
            if (eglProp.isNotEmpty()) {
                when {
                    eglProp.contains("adreno", ignoreCase = true) -> {
                        vendor = "adreno"
                        model = eglProp
                    }
                    eglProp.contains("mali", ignoreCase = true) -> {
                        vendor = "mali"
                        model = eglProp
                    }
                    eglProp.contains("powervr", ignoreCase = true) -> {
                        vendor = "powervr"
                        model = eglProp
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "GPU probe failed", e)
        }

        return Pair(vendor, model)
    }

    /**
     * Read CPU temperature from thermal zones.
     * Returns temperature in Celsius (may be 0.0 if unavailable).
     */
    private fun readCpuTemperature(): Double {
        try {
            val thermalDir = File("/sys/class/thermal/")
            val zones = thermalDir.listFiles { f ->
                f.isDirectory && f.name.startsWith("thermal_zone")
            } ?: return 30.0

            for (zone in zones.sortedBy { it.name }) {
                val typeFile = File(zone, "type")
                val tempFile = File(zone, "temp")
                if (!typeFile.exists() || !tempFile.exists()) continue

                val type = typeFile.readText().trim()
                // Look for CPU-related thermal zones
                if (type.contains("cpu", ignoreCase = true) ||
                    type.contains("soc", ignoreCase = true) ||
                    type.contains("skin", ignoreCase = true)
                ) {
                    val tempMilli = tempFile.readText().trim().toIntOrNull() ?: continue
                    // Some zones report in millidegrees, some in degrees
                    return if (tempMilli > 1000) tempMilli / 1000.0
                    else tempMilli.toDouble()
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Temperature read failed", e)
        }
        return 30.0
    }

    private fun readSystemProperty(name: String): String {
        return try {
            Class.forName("android.os.SystemProperties")
                .getMethod("get", String::class.java)
                .invoke(null, name) as? String ?: ""
        } catch (e: Exception) {
            ""
        }
    }
}
