package ai.awiki.awikime

import android.content.Context
import android.util.Log
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager

/**
 * Enqueues the expedited sync window from a BroadcastReceiver. Enqueue is the
 * only WorkManager call allowed on the EMAS MESSAGE callback path.
 */
object AliveBackgroundSyncScheduler {
    internal const val UNIQUE_WORK_NAME = "awiki-alive-background-sync"

    fun enqueue(context: Context) {
        val request = OneTimeWorkRequestBuilder<AliveBackgroundSyncWorker>()
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .addTag(UNIQUE_WORK_NAME)
            .build()
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
            UNIQUE_WORK_NAME,
            ExistingWorkPolicy.REPLACE,
            request,
        )
        Log.i("AWikiRemotePush", "alive_background_sync enqueue")
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context.applicationContext)
            .cancelUniqueWork(UNIQUE_WORK_NAME)
    }
}
