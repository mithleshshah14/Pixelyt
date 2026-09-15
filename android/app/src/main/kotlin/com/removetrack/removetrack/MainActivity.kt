package com.removetrack.removetrack

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "removetrack/picker"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "getLaunchAction" -> result.success(intent?.action)
                "returnPickedImage" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("NO_PATH", "Missing path argument", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(path)
                        val uri: Uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            file
                        )
                        val resultIntent = Intent().apply {
                            data = uri
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        setResult(Activity.RESULT_OK, resultIntent)
                        result.success(null)
                        finish()
                    } catch (e: Exception) {
                        result.error("RETURN_FAILED", e.message, null)
                    }
                }
                "cancelPicker" -> {
                    setResult(Activity.RESULT_CANCELED)
                    result.success(null)
                    finish()
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }
}
