package com.example.aapli_society
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // Must exist before any FCM message arrives, or Android silently drops
        // the notification tray display (see AndroidManifest.xml's
        // default_notification_channel_id meta-data, which points here).
        // High importance = heads-up/sound for visitor approval, gate/SOS,
        // security alerts - matches the "high" priority the backend already
        // sets on every push (lib/v1/fcm.js sendToTokens).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "high_importance_channel",
                "Alerts & Notices",
                NotificationManager.IMPORTANCE_HIGH,
            )
            channel.description = "Visitor approvals, gate/SOS alerts, notices, bills and tenancy updates"
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }
}