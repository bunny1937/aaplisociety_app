package com.example.aapli_society
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.RingtoneManager
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

            // Separate channel for SOS, because channel settings are per-channel
            // and immutable once created: anything we want to behave differently
            // for emergencies CANNOT be done by changing the payload, it has to
            // be its own channel. The backend already tags SOS pushes with
            // channelId "sos_channel" (see lib/v1/notify.js).
            //
            // The two settings that matter:
            //   setBypassDnd(true)  - the notification is delivered even when
            //                         the phone is in Do Not Disturb. This is
            //                         the ONLY supported way to be heard through
            //                         DND, and it requires the user to grant the
            //                         app DND access once in system settings.
            //   ALARM audio usage   - plays on the alarm stream, which silent
            //                         mode does not mute (the notification
            //                         stream, used by the default channel, is).
            //
            // Note this covers the tray notification. The continuous
            // ring-until-acknowledged loop is driven from Dart in
            // lib/core/sos/sos_alarm.dart, because a single notification sound
            // plays once and stops.
            val sosChannel = NotificationChannel(
                "sos_channel",
                "Emergency SOS",
                NotificationManager.IMPORTANCE_HIGH,
            )
            sosChannel.description =
                "Emergency alerts raised from a flat or from the gate. Rings even on silent."
            sosChannel.setBypassDnd(true)
            sosChannel.enableVibration(true)
            sosChannel.vibrationPattern = longArrayOf(0, 600, 250, 600, 250, 600)
            sosChannel.lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            sosChannel.setShowBadge(true)
            sosChannel.setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
                AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .build(),
            )
            manager?.createNotificationChannel(sosChannel)
        }
    }
}
