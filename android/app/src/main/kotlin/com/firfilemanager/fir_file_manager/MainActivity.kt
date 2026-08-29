package com.firfilemanager.fir_file_manager

import android.content.ClipData
import android.content.Intent
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val fileActionsChannel = "fir_file_manager/file_actions"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            fileActionsChannel,
        ).setMethodCallHandler { call, result ->
            val path = call.argument<String>("path")
            if (path.isNullOrBlank()) {
                result.error("INVALID_PATH", "A file path is required.", null)
                return@setMethodCallHandler
            }

            when (call.method) {
                "editFile" -> openFile(path, Intent.ACTION_EDIT, true, result)
                "openFile" -> openFile(path, Intent.ACTION_VIEW, false, result)
                "chooseAppAndOpen" ->
                    openFile(path, Intent.ACTION_VIEW, true, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun openFile(
        path: String,
        action: String,
        showChooser: Boolean,
        result: MethodChannel.Result,
    ) {
        val file = File(path)
        if (!file.isFile) {
            result.error("FILE_NOT_FOUND", "File does not exist: $path", null)
            return
        }

        try {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file,
            )
            val mimeType = if (action == Intent.ACTION_EDIT) {
                "text/plain"
            } else {
                val extension = file.extension.lowercase()
                MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
                    ?: "*/*"
            }
            val intent = Intent(action).apply {
                setDataAndType(uri, mimeType)
                clipData = ClipData.newRawUri(file.name, uri)
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            }

            if (intent.resolveActivity(packageManager) == null) {
                result.error(
                    "EDITOR_NOT_FOUND",
                    "No application can handle this file.",
                    null,
                )
                return
            }

            val launchIntent = if (showChooser) {
                Intent.createChooser(
                    intent,
                    if (action == Intent.ACTION_EDIT) {
                        "Düzenleyici seç"
                    } else {
                        "Uygulama seç"
                    },
                )
            } else {
                intent
            }
            startActivity(launchIntent)
            result.success(true)
        } catch (error: Exception) {
            result.error("OPEN_FAILED", error.message, null)
        }
    }
}
