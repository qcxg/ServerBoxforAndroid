package tech.lolli.toolbox

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Environment
import android.Manifest
import android.net.Uri
import android.provider.Settings
import android.webkit.MimeTypeMap
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.Context
import android.content.IntentFilter
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.appwidget.AppWidgetManager
import tech.lolli.toolbox.widget.HomeWidget
import java.io.File

class MainActivity: FlutterFragmentActivity() {
    private lateinit var channel: MethodChannel
    private val ACTION_UPDATE_SESSIONS = "tech.lolli.toolbox.ACTION_UPDATE_SESSIONS"
    private val ACTION_DISCONNECT_SESSION = "tech.lolli.toolbox.ACTION_DISCONNECT_SESSION"
    private val ACTION_STOP_ALL_CONNECTIONS = "tech.lolli.toolbox.STOP_ALL_CONNECTIONS"
    private var stopAllReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val binaryMessenger = flutterEngine.dartExecutor.binaryMessenger

        channel = MethodChannel(binaryMessenger, "tech.lolli.toolbox/main_chan")
        channel.setMethodCallHandler { method, result ->
                when (method.method) {
                    "sendToBackground" -> {
                        moveTaskToBack(true)
                        result.success(null)
                    }
                    "isServiceRunning" -> {
                        result.success(ForegroundService.isRunning)
                    }
                    "startService" -> {
                        try {
                            reqPerm()
                            val serviceIntent = Intent(this@MainActivity, ForegroundService::class.java)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(serviceIntent)
                            } else {
                                startService(serviceIntent)
                            }
                            result.success(null)
                        } catch (e: Exception) {
                            // Log error but don't crash
                            android.util.Log.e("MainActivity", "Failed to start service: ${e.message}")
                            result.error("SERVICE_ERROR", e.message, null)
                        }
                    }
                    "stopService" -> {
                        val serviceIntent = Intent(this@MainActivity, ForegroundService::class.java)
                        stopService(serviceIntent)
                        result.success(null)
                    }
                    "showToast" -> {
                        val message = method.arguments as? String
                        if (message.isNullOrBlank()) {
                            result.success(null)
                        } else {
                            runOnUiThread {
                                Toast.makeText(applicationContext, message, Toast.LENGTH_LONG).show()
                            }
                            result.success(null)
                        }
                    }
                    "hasStorageAccess" -> {
                        val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.R ||
                            Environment.isExternalStorageManager()
                        result.success(granted)
                    }
                    "requestStorageAccess" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R ||
                            Environment.isExternalStorageManager()) {
                            result.success(true)
                        } else {
                            try {
                                val intent = Intent(
                                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                    Uri.parse("package:$packageName")
                                )
                                startActivity(intent)
                                result.success(false)
                            } catch (e: Exception) {
                                try {
                                    startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                                    result.success(false)
                                } catch (fallback: Exception) {
                                    result.error("STORAGE_SETTINGS_ERROR", fallback.message, null)
                                }
                            }
                        }
                    }
                    "openFileExternally" -> {
                        val args = method.arguments as? Map<*, *>
                        val path = args?.get("path") as? String
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_PATH", "File path is empty", null)
                        } else {
                            openFileExternally(path, result)
                        }
                    }
                    "exitApp" -> {
                        result.success(null)
                        stopService(Intent(this@MainActivity, ForegroundService::class.java))
                        finishAndRemoveTask()
                        Handler(Looper.getMainLooper()).postDelayed({
                            android.os.Process.killProcess(android.os.Process.myPid())
                        }, 350)
                    }
                    "updateHomeWidget" -> {
                        val intent = Intent(this@MainActivity, HomeWidget::class.java)
                        intent.action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                        sendBroadcast(intent)
                        result.success(null)
                    }
                    "updateSessions" -> {
                        try {
                            val serviceIntent = Intent(this@MainActivity, ForegroundService::class.java)
                            serviceIntent.action = ACTION_UPDATE_SESSIONS
                            serviceIntent.putExtra("payload", method.arguments as String)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(serviceIntent)
                            } else {
                                startService(serviceIntent)
                            }
                            result.success(null)
                        } catch (e: Exception) {
                            android.util.Log.e("MainActivity", "Failed to update sessions: ${e.message}")
                            result.error("SERVICE_ERROR", e.message, null)
                        }
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
        }

        // Handle intent if launched via notification action
        handleActionIntent(intent)

        // Register broadcast receiver for stop all connections
        setupStopAllReceiver()
    }

    private fun openFileExternally(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.isFile) {
            result.error("FILE_NOT_FOUND", "File does not exist: $path", null)
            return
        }

        try {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.file_provider",
                file,
            )
            val extension = file.extension.lowercase()
            val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
                ?: when (extension) {
                    "txt", "log", "md", "markdown", "json", "json5", "jsonl",
                    "xml", "yaml", "yml", "toml", "ini", "conf", "config",
                    "sh", "bash", "zsh", "fish", "dart", "js", "jsx", "ts",
                    "tsx", "html", "css", "py", "go", "rs", "java", "kt",
                    "kts", "c", "cc", "cpp", "h", "hpp", "php", "rb", "swift" ->
                        "text/plain"
                    else -> "application/octet-stream"
                }
            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime)
                clipData = ClipData.newRawUri("file", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT)
            }
            startActivity(Intent.createChooser(viewIntent, null))
            result.success(true)
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Failed to open file externally", e)
            result.error("OPEN_FILE_ERROR", e.message, null)
        }
    }

    private fun reqPerm() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        
        try {
            // Check if we already have the permission to avoid unnecessary prompts
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
                // Check if we should show rationale
                if (ActivityCompat.shouldShowRequestPermissionRationale(this, Manifest.permission.POST_NOTIFICATIONS)) {
                    android.util.Log.i("MainActivity", "User previously denied notification permission")
                }
                
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    123,
                )
            }
        } catch (e: Exception) {
            // Log error but don't crash
            android.util.Log.e("MainActivity", "Failed to request permissions: ${e.message}")
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleActionIntent(intent)
    }

    private fun handleActionIntent(intent: Intent?) {
        if (intent == null) return
        when (intent.action) {
            ACTION_DISCONNECT_SESSION -> {
                val sessionId = intent.getStringExtra("session_id")
                if (sessionId != null && ::channel.isInitialized) {
                    try {
                        channel.invokeMethod("disconnectSession", mapOf("id" to sessionId))
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "Failed to invoke disconnect: ${e.message}")
                    }
                }
            }
        }
    }

    private fun setupStopAllReceiver() {
        stopAllReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == ACTION_STOP_ALL_CONNECTIONS && ::channel.isInitialized) {
                    try {
                        channel.invokeMethod("stopAllConnections", null)
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "Failed to invoke stopAllConnections: ${e.message}")
                    }
                }
            }
        }
        val filter = IntentFilter(ACTION_STOP_ALL_CONNECTIONS)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.registerReceiver(this, stopAllReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(stopAllReceiver, filter)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 123) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                android.util.Log.i("MainActivity", "Notification permission granted")
            } else {
                android.util.Log.w("MainActivity", "Notification permission denied")
                // Optionally inform user about the limitation
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopAllReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "Failed to unregister receiver: ${e.message}")
            }
            stopAllReceiver = null
        }
    }
}
