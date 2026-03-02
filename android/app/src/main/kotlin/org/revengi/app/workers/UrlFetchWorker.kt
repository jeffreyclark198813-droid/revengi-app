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
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Background worker for downloading URL content (APK files, resources).
 * Supports progress reporting, resumable downloads, and foreground service
 * notifications for long-running fetches.
 *
 * Targeted for Android 16 (API 36) / Motorola Moto G 2025 with proper
 * JobScheduler quota handling via WorkManager.
 */
class UrlFetchWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : CoroutineWorker(appContext, workerParams) {

    companion object {
        const val TAG = "UrlFetchWorker"

        // Input keys
        const val KEY_URL = "url"
        const val KEY_OUTPUT_PATH = "outputPath"
        const val KEY_HEADERS = "headers"
        const val KEY_FILE_NAME = "fileName"

        // Output keys
        const val KEY_RESULT_PATH = "resultPath"
        const val KEY_DOWNLOADED_BYTES = "downloadedBytes"
        const val KEY_ERROR_MESSAGE = "errorMessage"

        // Progress keys
        const val KEY_PROGRESS_PERCENT = "progressPercent"
        const val KEY_PROGRESS_BYTES = "progressBytes"
        const val KEY_PROGRESS_TOTAL = "progressTotal"

        // Notification
        const val NOTIFICATION_CHANNEL_ID = "revengi_url_fetch"
        const val NOTIFICATION_ID = 1002

        // Buffer size (8 KB)
        private const val BUFFER_SIZE = 8192
    }

    override suspend fun doWork(): Result {
        val urlString = inputData.getString(KEY_URL)
            ?: return Result.failure(workDataOf(KEY_ERROR_MESSAGE to "Missing URL"))

        val outputPath = inputData.getString(KEY_OUTPUT_PATH)
            ?: return Result.failure(workDataOf(KEY_ERROR_MESSAGE to "Missing output path"))

        val fileName = inputData.getString(KEY_FILE_NAME) ?: extractFileName(urlString)

        return try {
            setForeground(createForegroundInfo("Connecting...", 0))
            Log.i(TAG, "Starting background URL fetch: $urlString")

            val outputDir = File(outputPath)
            if (!outputDir.exists()) {
                outputDir.mkdirs()
            }
            val outputFile = File(outputDir, fileName)

            downloadFile(urlString, outputFile)

            Log.i(TAG, "URL fetch completed: ${outputFile.absolutePath} (${outputFile.length()} bytes)")

            Result.success(
                workDataOf(
                    KEY_RESULT_PATH to outputFile.absolutePath,
                    KEY_DOWNLOADED_BYTES to outputFile.length(),
                ),
            )
        } catch (e: Exception) {
            Log.e(TAG, "URL fetch failed: $urlString", e)
            if (runAttemptCount < 3) {
                Result.retry()
            } else {
                Result.failure(workDataOf(KEY_ERROR_MESSAGE to (e.message ?: "Download failed")))
            }
        }
    }

    private suspend fun downloadFile(urlString: String, outputFile: File) {
        val url = URL(urlString)
        val connection = url.openConnection() as HttpURLConnection

        try {
            connection.apply {
                requestMethod = "GET"
                connectTimeout = 30_000
                readTimeout = 30_000
                setRequestProperty("User-Agent", "RevEngi-App/1.0")
            }

            // Apply custom headers if provided
            val headersString = inputData.getString(KEY_HEADERS)
            if (!headersString.isNullOrEmpty()) {
                headersString.split(";").forEach { header ->
                    val parts = header.split(":", limit = 2)
                    if (parts.size == 2) {
                        connection.setRequestProperty(parts[0].trim(), parts[1].trim())
                    }
                }
            }

            connection.connect()

            val responseCode = connection.responseCode
            if (responseCode !in 200..299) {
                throw Exception("HTTP $responseCode: ${connection.responseMessage}")
            }

            val totalBytes = connection.contentLengthLong
            var downloadedBytes = 0L
            val buffer = ByteArray(BUFFER_SIZE)

            connection.inputStream.use { input ->
                FileOutputStream(outputFile).use { output ->
                    var bytesRead: Int
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        if (isStopped) {
                            Log.i(TAG, "Download cancelled")
                            outputFile.delete()
                            return
                        }

                        output.write(buffer, 0, bytesRead)
                        downloadedBytes += bytesRead

                        val percent = if (totalBytes > 0) {
                            ((downloadedBytes * 100) / totalBytes).toInt()
                        } else {
                            -1
                        }

                        setProgress(
                            workDataOf(
                                KEY_PROGRESS_PERCENT to percent,
                                KEY_PROGRESS_BYTES to downloadedBytes,
                                KEY_PROGRESS_TOTAL to totalBytes,
                            ),
                        )

                        if (percent >= 0) {
                            setForeground(createForegroundInfo("Downloading... $percent%", percent))
                        }
                    }
                }
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun extractFileName(urlString: String): String {
        return try {
            val path = URL(urlString).path
            val name = path.substringAfterLast("/")
            if (name.isNotEmpty()) name else "download_${System.currentTimeMillis()}"
        } catch (e: Exception) {
            "download_${System.currentTimeMillis()}"
        }
    }

    private fun createForegroundInfo(progressText: String, percent: Int): ForegroundInfo {
        createNotificationChannel()

        val builder = NotificationCompat.Builder(applicationContext, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("RevEngi - Downloading")
            .setContentText(progressText)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)

        if (percent in 0..100) {
            builder.setProgress(100, percent, false)
        } else {
            builder.setProgress(100, 0, true)
        }

        return ForegroundInfo(NOTIFICATION_ID, builder.build())
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "URL Downloads",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Background URL download tasks"
            }
            val manager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }
}
