package com.openagent.openagent.automation

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicInteger

/**
 * Screenshot helper using the official [MediaProjection] API (Android 5.0+).
 *
 * Call flow:
 *   1. Dart requests a screenshot.
 *   2. If we already have an active MediaProjection (cached), use it.
 *   3. If we don't, reply null — the Dart PermissionGuide page should start
 *      the grant flow via the registered ActivityResult launcher.
 *
 * For simplicity this MVP takes ONE screenshot at a time on a blocking call.
 * In production wrap this in a suspendCancellableCoroutine with a timeout.
 */
object ScreenshotManager {

    private const val TAG = "OAScreenshot"
    private const val VIRTUAL_DISPLAY_NAME = "OAScreenCap"

    // The MediaProjection permission intent must be issued from an Activity
    // and returns to onActivityResult / ActivityResultContracts. Because the
    // Flutter host activity doesn't expose a direct launcher for this yet,
    // the FIRST screenshot call will likely return null, asking the user to
    // first grant recording permission via the permission guide page.

    private var cachedProjection: MediaProjection? = null
    private var cachedResultCode: Int = 0
    private var cachedData: Intent? = null

    /** True once a MediaProjection has been granted (read by the status tool). */
    fun isReady(): Boolean = cachedProjection != null

    /** Called by [MainActivity] (via reflection later, or directly) once the
     *  user has granted MediaProjection so subsequent calls succeed silently. */
    fun cacheProjection(manager: MediaProjectionManager, resultCode: Int, data: Intent) {
        cachedResultCode = resultCode
        cachedData = data
        cachedProjection = manager.getMediaProjection(resultCode, data)
    }

    fun takeScreenshot(activity: Activity, outFile: File): Boolean {
        if (cachedProjection == null) {
            Log.w(TAG, "No cached MediaProjection — ask user to grant permission first.")
            return false
        }
        val wm = activity.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        wm.defaultDisplay.getRealMetrics(metrics)
        val w = metrics.widthPixels
        val h = metrics.heightPixels
        val dpi = metrics.densityDpi

        val reader = ImageReader.newInstance(w, h, android.graphics.PixelFormat.RGBA_8888, 2)
        val handler = Handler(Looper.getMainLooper())
        val display: VirtualDisplay?
        try {
            display = cachedProjection!!.createVirtualDisplay(
                VIRTUAL_DISPLAY_NAME,
                w, h, dpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader.surface,
                null,
                handler
            )
        } catch (t: Throwable) {
            Log.e(TAG, "createVirtualDisplay failed", t)
            return false
        }
        // Small delay so the display has a frame ready.
        Thread.sleep(400)
        var image: Image? = null
        var fos: FileOutputStream? = null
        try {
            image = reader.acquireLatestImage()
            if (image == null) {
                Log.w(TAG, "No image acquired")
                return false
            }
            val planes = image.planes
            val buffer: ByteBuffer = planes[0].buffer
            val pixelStride = planes[0].pixelStride
            val rowStride = planes[0].rowStride
            val rowPadding = rowStride - pixelStride * w
            val bitmap = Bitmap.createBitmap(w + rowPadding / pixelStride, h, Bitmap.Config.ARGB_8888)
            bitmap.copyPixelsFromBuffer(buffer)
            val cropped = Bitmap.createBitmap(bitmap, 0, 0, w, h)
            fos = FileOutputStream(outFile)
            cropped.compress(Bitmap.CompressFormat.PNG, 100, fos)
            fos.flush()
            bitmap.recycle()
            cropped.recycle()
            return outFile.exists() && outFile.length() > 4096
        } catch (t: Throwable) {
            Log.e(TAG, "screencap failed", t)
            return false
        } finally {
            runCatching { image?.close() }
            runCatching { fos?.close() }
            runCatching { display.release() }
            runCatching { reader.close() }
        }
    }
}
