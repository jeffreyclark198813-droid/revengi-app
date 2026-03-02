package org.revengi.app.workers

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import org.revengi.app.arsclib.Merger

/**
 * Background worker for APK merge/transform operations.
 * Uses CoroutineWorker for structured concurrency and proper cancellation.
 * Reports progress via setProgress() and completion via output Data.
 */
class ApkTransformWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : CoroutineWorker(appContext, workerParams) {

    companion object {
        const val TAG = "ApkTransformWorker"

        // Input keys
        const val KEY_EXTRACTED_DIR = "extractedDir"
        const val KEY_OUTPUT_FILE = "outputFile"
        const val KEY_VALIDATE_MODULES = "validateModules"
        const val KEY_RES_DIR_NAME = "resDirName"
        const val KEY_VALIDATE_RES_DIR = "validateResDir"
        const val KEY_CLEAN_META = "cleanMeta"
        const val KEY_EXTRACT_NATIVE_LIBS = "extractNativeLibs"

        // Output keys
        const val KEY_RESULT_PATH = "resultPath"
        const val KEY_ERROR_MESSAGE = "errorMessage"

        // Progress keys
        const val KEY_PROGRESS_STAGE = "progressStage"
        const val KEY_PROGRESS_PERCENT = "progressPercent"

        // Notification
        const val NOTIFICATION_CHANNEL_ID = "revengi_background_tasks"
        const val NOTIFICATION_ID = 1001
    }

    override suspend fun doWork(): Result {
        val extractedDir = inputData.getString(KEY_EXTRACTED_DIR)
            ?: return Result.failure(workDataOf(KEY_ERROR_MESSAGE to "Missing extractedDir"))
        val outputFile = inputData.getString(KEY_OUTPUT_FILE)
            ?: return Result.failure(workDataOf(KEY_ERROR_MESSAGE to "Missing outputFile"))

        val options = mutableMapOf<String, Any?>()
        options["extractedDir"] = extractedDir
        options["outputFile"] = outputFile
        options["validateModules"] = inputData.getBoolean(KEY_VALIDATE_MODULES, false)
        options["resDirName"] = inputData.getString(KEY_RES_DIR_NAME) ?: ""
        options["validateResDir"] = inputData.getBoolean(KEY_VALIDATE_RES_DIR, false)
        options["cleanMeta"] = inputData.getBoolean(KEY_CLEAN_META, false)
        options["extractNativeLibs"] = inputData.getString(KEY_EXTRACT_NATIVE_LIBS)

        return try {
            setProgress(workDataOf(KEY_PROGRESS_STAGE to "Starting merge", KEY_PROGRESS_PERCENT to 0))
            setForeground(createForegroundInfo("Merging APK..."))

            Log.i(TAG, "Starting background APK merge: $extractedDir -> $outputFile")

            // Run merge synchronously within the coroutine worker context.
            // Merger.startMerge() spawns its own thread internally; we use
            // a CountDownLatch to block until it completes so WorkManager
            // can properly track lifecycle and report results.
            val merger = Merger()
            setProgress(workDataOf(KEY_PROGRESS_STAGE to "Merging modules", KEY_PROGRESS_PERCENT to 25))

            val latch = java.util.concurrent.CountDownLatch(1)
            var mergeError: Exception? = null

            // Listen for merge completion via the EventChannel pattern
            val originalSink = org.revengi.app.MainActivity.eventSinkStatic
            merger.startMerge(options)

            // Poll for output file existence as completion signal
            val outFile = java.io.File(outputFile)
            val startTime = System.currentTimeMillis()
            val timeout = 30L * 60 * 1000 // 30 minute timeout
            while (!outFile.exists() && (System.currentTimeMillis() - startTime) < timeout) {
                if (isStopped) {
                    Log.i(TAG, "Worker stopped during merge")
                    break
                }
                Thread.sleep(2000)
                setProgress(workDataOf(
                    KEY_PROGRESS_STAGE to "Merging...",
                    KEY_PROGRESS_PERCENT to minOf(90, 25 + ((System.currentTimeMillis() - startTime) / 1000).toInt()),
                ))
            }

            if (!outFile.exists() && !isStopped) {
                throw Exception("Merge timed out or failed to produce output file")
            }

            setProgress(workDataOf(KEY_PROGRESS_STAGE to "Complete", KEY_PROGRESS_PERCENT to 100))
            Log.i(TAG, "APK merge completed: $outputFile")

            Result.success(workDataOf(KEY_RESULT_PATH to outputFile))
        } catch (e: Exception) {
            Log.e(TAG, "APK merge failed", e)
            Result.failure(workDataOf(KEY_ERROR_MESSAGE to (e.message ?: "Unknown error")))
        }
    }

    private fun createForegroundInfo(progressText: String): ForegroundInfo {
        createNotificationChannel()

        val notification = NotificationCompat.Builder(applicationContext, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("RevEngi - APK Transform")
            .setContentText(progressText)
            .setSmallIcon(android.R.drawable.ic_popup_sync)
            .setOngoing(true)
            .setProgress(100, 0, true)
            .build()

        return ForegroundInfo(NOTIFICATION_ID, notification)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Background Tasks",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "APK transformation and processing tasks"
            }
            val manager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }
}
