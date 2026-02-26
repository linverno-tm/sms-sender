package com.example.sms

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.telephony.SmsManager
import androidx.core.app.NotificationCompat
import java.util.concurrent.Executors

class BulkSmsForegroundService : Service() {
    private val repository by lazy { BulkSmsRepository(applicationContext) }
    private val executor = Executors.newSingleThreadExecutor()
    @Volatile
    private var stopRequested = false
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        repository.close()
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_RESUME
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification(repository.getStatus()))

        when (action) {
            ACTION_START -> {
                val message = intent?.getStringExtra(EXTRA_MESSAGE).orEmpty()
                val numbers = intent?.getStringArrayListExtra(EXTRA_NUMBERS)?.toList().orEmpty()
                if (numbers.isNotEmpty() && message.isNotBlank()) {
                    stopRequested = false
                    executor.execute {
                        repository.createNewCampaign(numbers, message)
                        processQueue()
                    }
                }
            }

            ACTION_RESUME -> {
                if (repository.hasUnfinishedCampaign()) {
                    stopRequested = false
                    executor.execute { processQueue() }
                } else {
                    stopSelf()
                }
            }

            ACTION_STOP -> {
                stopRequested = true
                repository.setState("stopped")
                updateForegroundNotification(repository.getStatus())
                stopSelf()
            }
        }

        return START_STICKY
    }

    private fun processQueue() {
        acquireWakeLock()
        try {
            repository.setState("sending")
            while (!stopRequested) {
                val nextItem = repository.nextPending() ?: break
                repository.markSending(nextItem.position, nextItem.number)
                updateForegroundNotification(repository.getStatus())

                val sendResult = sendSms(nextItem.number, repository.getStatus().message.orEmpty())
                if (sendResult == null) {
                    repository.markSent(nextItem.id, nextItem.position, nextItem.number)
                } else {
                    repository.markFailed(nextItem.id, nextItem.position, nextItem.number, sendResult)
                }
                updateForegroundNotification(repository.getStatus())

                Thread.sleep(SEND_DELAY_MS)
            }

            val status = repository.getStatus()
            if (status.pending == 0) {
                repository.setState("completed")
            } else if (stopRequested) {
                repository.setState("stopped")
            }
            updateForegroundNotification(repository.getStatus())
        } catch (e: Exception) {
            repository.setState("stopped")
            updateForegroundNotification(repository.getStatus())
        } finally {
            releaseWakeLock()
            stopSelf()
        }
    }

    private fun sendSms(number: String, message: String): String? {
        return try {
            val smsManager = SmsManager.getDefault()
            val parts = smsManager.divideMessage(message)
            if (parts.size > 1) {
                smsManager.sendMultipartTextMessage(number, null, ArrayList(parts), null, null)
            } else {
                smsManager.sendTextMessage(number, null, message, null, null)
            }
            null
        } catch (e: Exception) {
            e.message ?: "send_failed"
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) {
            return
        }
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "sms:bulkWakeLock").apply {
            setReferenceCounted(false)
            acquire(10 * 60 * 1000L)
        }
    }

    private fun releaseWakeLock() {
        val lock = wakeLock
        if (lock != null && lock.isHeld) {
            lock.release()
        }
        wakeLock = null
    }

    private fun updateForegroundNotification(status: BulkStatus) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(status))
    }

    private fun buildNotification(status: BulkStatus): Notification {
        val total = status.total.coerceAtLeast(1)
        val progressValue = ((status.sent + status.failed) * 100 / total).coerceIn(0, 100)
        val text = "Юборилди: ${status.sent}, Хато: ${status.failed}, Қолди: ${status.pending}"

        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_more)
            .setContentTitle("СМС юборилмоқда...")
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setOngoing(status.state == "sending")
            .setProgress(100, progressValue, status.total == 0)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Bulk SMS",
            NotificationManager.IMPORTANCE_LOW,
        )
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val ACTION_START = "com.example.sms.action.START_BULK_SMS"
        private const val ACTION_STOP = "com.example.sms.action.STOP_BULK_SMS"
        private const val ACTION_RESUME = "com.example.sms.action.RESUME_BULK_SMS"
        private const val EXTRA_NUMBERS = "extra_numbers"
        private const val EXTRA_MESSAGE = "extra_message"
        private const val NOTIFICATION_ID = 1177
        private const val CHANNEL_ID = "bulk_sms_channel"
        private const val SEND_DELAY_MS = 2000L

        fun start(context: Context, message: String, numbers: ArrayList<String>) {
            val intent = Intent(context, BulkSmsForegroundService::class.java).apply {
                action = ACTION_START
                putStringArrayListExtra(EXTRA_NUMBERS, numbers)
                putExtra(EXTRA_MESSAGE, message)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun resume(context: Context) {
            val intent = Intent(context, BulkSmsForegroundService::class.java).apply {
                action = ACTION_RESUME
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, BulkSmsForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }
}
