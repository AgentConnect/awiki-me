package ai.awiki.awikime.push

import android.content.Context
import com.alibaba.sdk.android.push.notification.CPushMessage

/** Debug manifest replaces the regular receiver, so each callback has one owner. */
class ContinuousUrgentProbePushReceiver : AwikiAliyunPushReceiver() {
    override fun onMessage(context: Context, message: CPushMessage) {
        if (!ContinuousUrgentServiceProbe.receive(context, message.content)) {
            super.onMessage(context, message)
        }
    }
}
