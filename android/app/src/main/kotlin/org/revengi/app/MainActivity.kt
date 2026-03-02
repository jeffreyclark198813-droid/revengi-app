package org.revengi.app

import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.revengi.app.arsclib.Merger
import org.revengi.app.workers.WorkManagerHelper
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class MainActivity : FlutterActivity() {
    private val myChannel = "flutter.native/helper"
    private val logChannel = "flutter.native/logs"
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            myChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceInfo" -> {
                    val deviceInfo: HashMap<String, String> = getDeviceInfo()
                    if (deviceInfo.isNotEmpty()) {
                        result.success(deviceInfo)
                    } else {
                        result.error("UNAVAILABLE", "Device info not available.", null)
                    }
                }

                "getTotalRAM" -> {
                    val totalRAM = getTotalRAM(this)
                    result.success(totalRAM)
                }

                "startMerge" -> {
                    val options = call.arguments as? Map<String, Any?>
                    Merger().startMerge(options)
                    result.success(true)
                }

                "zipApks" -> {
                    val apkPaths = call.argument<List<String>>("apkPaths")
                    val outputPath = call.argument<String>("outputPath")
                    Thread {
                        val success = zipApks(apkPaths!!, outputPath!!)
                        result.success(success)
                    }.start()
                }

                // --- WorkManager Background Task Handlers ---

                "scheduleBackgroundMerge" -> {
                    try {
                        val options = call.arguments as? Map<String, Any?> ?: emptyMap()
                        val requireCharging = options["requireCharging"] as? Boolean ?: false
                        val workId = WorkManagerHelper.scheduleApkTransform(
                            this@MainActivity,
                            options,
                            requireCharging,
                        )
                        result.success(mapOf("workId" to workId, "scheduled" to true))
                    } catch (e: Exception) {
                        result.error("SCHEDULE_ERROR", e.message, null)
                    }
                }

                "scheduleUrlFetch" -> {
                    try {
                        val url = call.argument<String>("url")
                            ?: return@setMethodCallHandler result.error("INVALID_ARG", "Missing url", null)
                        val outputPath = call.argument<String>("outputPath")
                            ?: return@setMethodCallHandler result.error("INVALID_ARG", "Missing outputPath", null)
                        val fileName = call.argument<String>("fileName")
                        val headers = call.argument<String>("headers")
                        val wifiOnly = call.argument<Boolean>("wifiOnly") ?: false

                        val workId = WorkManagerHelper.scheduleUrlFetch(
                            this@MainActivity,
                            url,
                            outputPath,
                            fileName,
                            headers,
                            wifiOnly,
                        )
                        result.success(mapOf("workId" to workId, "scheduled" to true))
                    } catch (e: Exception) {
                        result.error("SCHEDULE_ERROR", e.message, null)
                    }
                }

                "cancelBackgroundWork" -> {
                    try {
                        val workId = call.argument<String>("workId")
                        if (workId != null) {
                            WorkManagerHelper.cancelWork(this@MainActivity, workId)
                        } else {
                            WorkManagerHelper.cancelAllWork(this@MainActivity)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CANCEL_ERROR", e.message, null)
                    }
                }

                "getBackgroundWorkStatus" -> {
                    try {
                        val workId = call.argument<String>("workId")
                        if (workId != null) {
                            val status = WorkManagerHelper.getWorkStatus(this@MainActivity, workId)
                            result.success(status)
                        } else {
                            result.error("INVALID_ARG", "Missing workId", null)
                        }
                    } catch (e: Exception) {
                        result.error("STATUS_ERROR", e.message, null)
                    }
                }

                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        if (ContextCompat.checkSelfPermission(
                                this@MainActivity,
                                android.Manifest.permission.POST_NOTIFICATIONS,
                            ) != PackageManager.PERMISSION_GRANTED
                        ) {
                            ActivityCompat.requestPermissions(
                                this@MainActivity,
                                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                                NOTIFICATION_PERMISSION_REQUEST_CODE,
                            )
                            result.success(false)
                        } else {
                            result.success(true)
                        }
                    } else {
                        // Pre-Android 13 -- no runtime permission needed
                        result.success(true)
                    }
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, logChannel)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(
                        arguments: Any?,
                        events: EventChannel.EventSink?,
                    ) {
                        eventSink = events
                        eventSinkStatic = events
                    }

                    override fun onCancel(arguments: Any?) {
                        eventSink = null
                        eventSinkStatic = null
                    }
                },
            )
    }

    private fun getDeviceInfo(): HashMap<String, String> {
        val deviceInfo = HashMap<String, String>()
        deviceInfo["version"] = System.getProperty("os.version")!!.toString()
        deviceInfo["device"] = Build.DEVICE
        deviceInfo["model"] = Build.MODEL
        deviceInfo["product"] = Build.PRODUCT
        deviceInfo["manufacturer"] = Build.MANUFACTURER
        deviceInfo["sdkVersion"] = Build.VERSION.SDK_INT.toString()
        deviceInfo["id"] = Build.ID
        return deviceInfo
    }

    private fun getTotalRAM(context: Context): Long {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)
        return memoryInfo.totalMem
    }

    @Throws(IOException::class)
    private fun zipApks(
        apkPaths: List<String>,
        outputPath: String,
    ): Boolean =
        try {
            ZipOutputStream(
                BufferedOutputStream(
                    FileOutputStream(outputPath),
                ),
            ).use { zipOutputStream ->
                zipOutputStream.setLevel(3)
                for (path in apkPaths) {
                    Log.i("ExtractAPK", "Adding: $path")
                    val file = File(path)
                    FileInputStream(file).use { fileInputStream ->
                        val entry = ZipEntry(file.name)
                        entry.time = file.lastModified()
                        entry.size = file.length()
                        zipOutputStream.putNextEntry(entry)
                        fileInputStream.copyTo(zipOutputStream)
                    }
                }
            }
            true
        } catch (e: Exception) {
            Log.e("ExtractAPK", "Error zipping APKs", e)
            false
        }

    companion object {
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 1100

        var eventSinkStatic: EventChannel.EventSink? = null

        @JvmStatic
        fun sendLog(
            msg: String,
            type: String = "success",
        ) {
            Handler(Looper.getMainLooper()).post {
                eventSinkStatic?.success(mapOf("msg" to msg, "type" to type))
            }
        }
    }
}
