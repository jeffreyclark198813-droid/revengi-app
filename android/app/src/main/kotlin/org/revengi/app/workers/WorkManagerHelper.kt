package org.revengi.app.workers

import android.content.Context
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit

/**
 * Centralized utility for scheduling and managing WorkManager tasks.
 * Provides methods for APK transforms and URL fetching with configurable
 * constraints appropriate for Android 16 (API 36) quota management.
 */
object WorkManagerHelper {
    private const val TAG = "WorkManagerHelper"

    // Work name prefixes for unique work identification
    private const val WORK_PREFIX_APK = "revengi_apk_transform_"
    private const val WORK_PREFIX_URL = "revengi_url_fetch_"

    /**
     * Schedule a background APK merge/transform operation.
     *
     * @param context Application context
     * @param options Map of merge options matching Merger.startMerge() parameters
     * @param requireCharging Whether to require the device to be charging
     * @return Unique work ID for tracking this task
     */
    fun scheduleApkTransform(
        context: Context,
        options: Map<String, Any?>,
        requireCharging: Boolean = false,
    ): String {
        val workId = WORK_PREFIX_APK + System.currentTimeMillis()

        val inputData = workDataOf(
            ApkTransformWorker.KEY_EXTRACTED_DIR to (options["extractedDir"] as? String),
            ApkTransformWorker.KEY_OUTPUT_FILE to (options["outputFile"] as? String),
            ApkTransformWorker.KEY_VALIDATE_MODULES to (options["validateModules"] as? Boolean ?: false),
            ApkTransformWorker.KEY_RES_DIR_NAME to (options["resDirName"] as? String ?: ""),
            ApkTransformWorker.KEY_VALIDATE_RES_DIR to (options["validateResDir"] as? Boolean ?: false),
            ApkTransformWorker.KEY_CLEAN_META to (options["cleanMeta"] as? Boolean ?: false),
            ApkTransformWorker.KEY_EXTRACT_NATIVE_LIBS to (options["extractNativeLibs"] as? String),
        )

        val constraints = Constraints.Builder()
            .setRequiresBatteryNotLow(true)
            .apply {
                if (requireCharging) setRequiresCharging(true)
            }
            .build()

        val workRequest = OneTimeWorkRequestBuilder<ApkTransformWorker>()
            .setInputData(inputData)
            .setConstraints(constraints)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .addTag(workId)
            .build()

        WorkManager.getInstance(context).enqueueUniqueWork(
            workId,
            ExistingWorkPolicy.KEEP,
            workRequest,
        )

        Log.i(TAG, "Scheduled APK transform: $workId")
        return workId
    }

    /**
     * Schedule a background URL fetch/download operation.
     *
     * @param context Application context
     * @param url URL to download
     * @param outputPath Directory path to save the downloaded file
     * @param fileName Optional filename override
     * @param headers Optional headers as semicolon-separated "key:value" pairs
     * @param wifiOnly Whether to restrict download to unmetered (Wi-Fi) networks
     * @return Unique work ID for tracking this task
     */
    fun scheduleUrlFetch(
        context: Context,
        url: String,
        outputPath: String,
        fileName: String? = null,
        headers: String? = null,
        wifiOnly: Boolean = false,
    ): String {
        val workId = WORK_PREFIX_URL + System.currentTimeMillis()

        val inputData = workDataOf(
            UrlFetchWorker.KEY_URL to url,
            UrlFetchWorker.KEY_OUTPUT_PATH to outputPath,
            UrlFetchWorker.KEY_FILE_NAME to fileName,
            UrlFetchWorker.KEY_HEADERS to headers,
        )

        val constraints = Constraints.Builder()
            .setRequiredNetworkType(if (wifiOnly) NetworkType.UNMETERED else NetworkType.CONNECTED)
            .setRequiresBatteryNotLow(true)
            .build()

        val workRequest = OneTimeWorkRequestBuilder<UrlFetchWorker>()
            .setInputData(inputData)
            .setConstraints(constraints)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .addTag(workId)
            .build()

        WorkManager.getInstance(context).enqueueUniqueWork(
            workId,
            ExistingWorkPolicy.KEEP,
            workRequest,
        )

        Log.i(TAG, "Scheduled URL fetch: $workId ($url)")
        return workId
    }

    /**
     * Cancel a specific background work by its unique ID.
     */
    fun cancelWork(context: Context, workId: String) {
        WorkManager.getInstance(context).cancelUniqueWork(workId)
        Log.i(TAG, "Cancelled work: $workId")
    }

    /**
     * Cancel all RevEngi background work.
     */
    fun cancelAllWork(context: Context) {
        WorkManager.getInstance(context).cancelAllWork()
        Log.i(TAG, "Cancelled all work")
    }

    /**
     * Get the current status of a specific work request.
     * Returns a map with status details suitable for passing to Flutter.
     */
    fun getWorkStatus(context: Context, workId: String): Map<String, Any?> {
        val workInfos = WorkManager.getInstance(context)
            .getWorkInfosForUniqueWork(workId)
            .get()

        if (workInfos.isNullOrEmpty()) {
            return mapOf("state" to "UNKNOWN", "workId" to workId)
        }

        val workInfo = workInfos.first()
        val result = mutableMapOf<String, Any?>(
            "workId" to workId,
            "state" to workInfo.state.name,
        )

        // Include progress data if running
        if (workInfo.state == WorkInfo.State.RUNNING) {
            val progress = workInfo.progress
            result["progressStage"] = progress.getString(ApkTransformWorker.KEY_PROGRESS_STAGE)
            result["progressPercent"] = progress.getInt(ApkTransformWorker.KEY_PROGRESS_PERCENT, -1)
            result["progressBytes"] = progress.getLong(UrlFetchWorker.KEY_PROGRESS_BYTES, -1)
            result["progressTotal"] = progress.getLong(UrlFetchWorker.KEY_PROGRESS_TOTAL, -1)
        }

        // Include output data if completed
        if (workInfo.state == WorkInfo.State.SUCCEEDED) {
            result["resultPath"] = workInfo.outputData.getString(ApkTransformWorker.KEY_RESULT_PATH)
                ?: workInfo.outputData.getString(UrlFetchWorker.KEY_RESULT_PATH)
            result["downloadedBytes"] = workInfo.outputData.getLong(UrlFetchWorker.KEY_DOWNLOADED_BYTES, -1)
        }

        // Include error if failed
        if (workInfo.state == WorkInfo.State.FAILED) {
            result["errorMessage"] = workInfo.outputData.getString(ApkTransformWorker.KEY_ERROR_MESSAGE)
                ?: workInfo.outputData.getString(UrlFetchWorker.KEY_ERROR_MESSAGE)
        }

        return result
    }

    /**
     * Get status of all RevEngi background tasks.
     * Returns a list of status maps for each active/recent task.
     */
    fun getAllWorkStatuses(context: Context): List<Map<String, Any?>> {
        val apkWork = WorkManager.getInstance(context)
            .getWorkInfosByTag(TAG)
            .get()

        return apkWork?.map { workInfo ->
            mapOf(
                "workId" to workInfo.id.toString(),
                "state" to workInfo.state.name,
                "tags" to workInfo.tags.toList(),
            )
        } ?: emptyList()
    }
}
