package kr.gieokhaejwo.gieokhaejwo

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createAlertChannel()
    }

    // 실종경보 푸시가 들어갈 알림 채널. 서버가 보내는 channel_id와 같아야 해요.
    private fun createAlertChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            ALERT_CHANNEL_ID,
            "실종경보",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply { description = "우리 동네 실종경보 알림" }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    companion object {
        const val ALERT_CHANNEL_ID = "missing_alerts"
    }
}
