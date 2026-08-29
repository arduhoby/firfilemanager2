package com.firfilemanager.fir_file_manager

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

object SmartSyncScheduler {
    private const val preferencesName = "fir_smartsync_schedules"

    fun schedule(context: Context, values: Map<String, Any?>) {
        val jobId = values["jobId"] as? String
            ?: throw IllegalArgumentException("jobId is required")
        val json = JSONObject()
        values.forEach { (key, value) ->
            when (value) {
                is List<*> -> json.put(key, JSONArray(value))
                null -> Unit
                else -> json.put(key, value)
            }
        }
        context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            .edit()
            .putString(jobId, json.toString())
            .apply()
        scheduleAlarm(context, jobId, json.optLong("nextRunAtMillis"))
    }

    fun cancel(context: Context, jobId: String, removeDefinition: Boolean = true) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        alarmManager.cancel(pendingIntent(context, jobId))
        if (removeDefinition) {
            context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
                .edit()
                .remove(jobId)
                .apply()
        }
    }

    fun scheduleAll(context: Context) {
        val preferences = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
        preferences.all.keys.forEach { jobId -> scheduleNext(context, jobId) }
    }

    fun scheduleNext(context: Context, jobId: String) {
        val preferences = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
        val raw = preferences.getString(jobId, null) ?: return
        val json = JSONObject(raw)
        val next = nextOccurrence(json, System.currentTimeMillis())
        if (next == null) {
            cancel(context, jobId)
            return
        }
        scheduleAlarm(context, jobId, next)
    }

    private fun scheduleAlarm(context: Context, jobId: String, atMillis: Long) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val operation = pendingIntent(context, jobId)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            !alarmManager.canScheduleExactAlarms()
        ) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, operation)
        } else {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                atMillis,
                operation,
            )
        }
    }

    private fun pendingIntent(context: Context, jobId: String): PendingIntent {
        val intent = Intent(context, SmartSyncAlarmReceiver::class.java)
            .setAction("fir.smartsync.RUN.$jobId")
            .putExtra("jobId", jobId)
        return PendingIntent.getBroadcast(
            context,
            jobId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun nextOccurrence(json: JSONObject, afterMillis: Long): Long? {
        return when (json.optString("scheduleType", "manual")) {
            "once" -> json.optLong("onceAtMillis").takeIf { it > afterMillis }
            "daily" -> nextDaily(json, afterMillis)
            "weekly" -> nextWeekly(json, afterMillis)
            else -> null
        }
    }

    private fun nextDaily(json: JSONObject, afterMillis: Long): Long {
        val calendar = Calendar.getInstance().apply {
            timeInMillis = afterMillis
            set(Calendar.HOUR_OF_DAY, json.optInt("hour"))
            set(Calendar.MINUTE, json.optInt("minute"))
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= afterMillis) add(Calendar.DAY_OF_YEAR, 1)
        }
        return calendar.timeInMillis
    }

    private fun nextWeekly(json: JSONObject, afterMillis: Long): Long? {
        val weekdays = json.optJSONArray("weekdays") ?: return null
        val selected = mutableSetOf<Int>()
        for (index in 0 until weekdays.length()) selected.add(weekdays.optInt(index))
        if (selected.isEmpty()) return null
        for (offset in 0..7) {
            val calendar = Calendar.getInstance().apply {
                timeInMillis = afterMillis
                add(Calendar.DAY_OF_YEAR, offset)
                set(Calendar.HOUR_OF_DAY, json.optInt("hour"))
                set(Calendar.MINUTE, json.optInt("minute"))
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val dartWeekday = if (calendar.get(Calendar.DAY_OF_WEEK) == Calendar.SUNDAY) {
                7
            } else {
                calendar.get(Calendar.DAY_OF_WEEK) - 1
            }
            if (selected.contains(dartWeekday) && calendar.timeInMillis > afterMillis) {
                return calendar.timeInMillis
            }
        }
        return null
    }

    fun definition(context: Context, jobId: String): JSONObject? {
        val raw = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            .getString(jobId, null) ?: return null
        return JSONObject(raw)
    }
}

class SmartSyncAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val jobId = intent.getStringExtra("jobId") ?: return
        val definition = SmartSyncScheduler.definition(context, jobId) ?: return
        val constraintsMet = networkConstraintMet(context, definition) &&
            chargingConstraintMet(context, definition)
        if (constraintsMet) {
            val serviceIntent = Intent(context, SmartSyncService::class.java)
                .putExtra("jobId", jobId)
                .putExtra("jobName", definition.optString("jobName", "Fir SmartSync"))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
            SmartSyncScheduler.scheduleNext(context, jobId)
        } else if (definition.optBoolean("runWhenAvailable", true)) {
            val retry = definition.toMap().toMutableMap()
            retry["nextRunAtMillis"] = System.currentTimeMillis() + 15 * 60 * 1000L
            SmartSyncScheduler.schedule(context, retry)
        } else {
            SmartSyncScheduler.scheduleNext(context, jobId)
        }
    }

    private fun networkConstraintMet(context: Context, definition: JSONObject): Boolean {
        val requireWifi = definition.optBoolean("requireWifi", false)
        val allowMobileData = definition.optBoolean("allowMobileData", false)
        if (!requireWifi && !allowMobileData) return true
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        val network = connectivity.activeNetwork ?: return false
        val capabilities = connectivity.getNetworkCapabilities(network) ?: return false
        if (requireWifi) {
            return capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
        }
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    private fun chargingConstraintMet(context: Context, definition: JSONObject): Boolean {
        if (!definition.optBoolean("requireCharging", false)) return true
        val battery = context.getSystemService(BatteryManager::class.java)
        return battery.isCharging
    }

    private fun JSONObject.toMap(): Map<String, Any?> {
        val result = mutableMapOf<String, Any?>()
        keys().forEach { key ->
            val value = get(key)
            result[key] = if (value is JSONArray) {
                (0 until value.length()).map { value.get(it) }
            } else {
                value
            }
        }
        return result
    }
}

class SmartSyncBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            SmartSyncScheduler.scheduleAll(context)
        }
    }
}

class SmartSyncService : Service() {
    private var engine: FlutterEngine? = null
    private val timeoutHandler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val jobId = intent?.getStringExtra("jobId") ?: return START_NOT_STICKY
        val jobName = intent.getStringExtra("jobName") ?: "Fir SmartSync"
        createNotificationChannel()
        startForeground(
            jobId.hashCode(),
            NotificationCompat.Builder(this, notificationChannelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(jobName)
                .setContentText("Synchronization is running")
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .build(),
        )

        val flutterLoader = FlutterInjector.instance().flutterLoader()
        flutterLoader.startInitialization(this)
        flutterLoader.ensureInitializationComplete(this, null)
        val flutterEngine = FlutterEngine(this)
        engine = flutterEngine
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            backgroundChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method == "complete") {
                val succeeded = call.argument<Boolean>("succeeded") ?: false
                updateCompletionNotification(jobId, jobName, succeeded)
                result.success(null)
                finish()
            } else {
                result.notImplemented()
            }
        }
        val entrypoint = DartExecutor.DartEntrypoint(
            flutterLoader.findAppBundlePath(),
            "smartSyncBackgroundMain",
        )
        flutterEngine.dartExecutor.executeDartEntrypoint(entrypoint, listOf(jobId))
        timeoutHandler.postDelayed({ finish() }, 6 * 60 * 60 * 1000L)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        timeoutHandler.removeCallbacksAndMessages(null)
        engine?.destroy()
        engine = null
        super.onDestroy()
    }

    private fun finish() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                notificationChannelId,
                "Fir SmartSync",
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }

    private fun updateCompletionNotification(
        notificationId: String,
        jobName: String,
        succeeded: Boolean,
    ) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(
            notificationId.hashCode(),
            NotificationCompat.Builder(this, notificationChannelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(jobName)
                .setContentText(
                    if (succeeded) "Synchronization completed" else "Synchronization failed",
                )
                .setAutoCancel(true)
                .build(),
        )
    }

    companion object {
        private const val notificationChannelId = "fir_smartsync"
        private const val backgroundChannel = "fir_file_manager/sync_background"
    }
}
