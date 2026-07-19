package ai.awiki.awikime

import android.app.Application
import android.util.Log
import com.alibaba.sdk.android.push.noonesdk.PushInitConfig
import com.alibaba.sdk.android.push.noonesdk.PushServiceFactory

class AwikiApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        if (!BuildConfig.AWIKI_EMAS_ENABLED) {
            return
        }
        try {
            val config = PushInitConfig.Builder()
                .application(this)
                .appKey(BuildConfig.AWIKI_EMAS_APP_KEY)
                .appSecret(BuildConfig.AWIKI_EMAS_APP_SECRET)
                .build()
            PushServiceFactory.init(config)
        } catch (error: Throwable) {
            Log.e("AWikiRemotePush", "EMAS early initialization failed", error)
        }
    }
}
