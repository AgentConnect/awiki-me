package ai.awiki.awikime

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val DOCUMENT_CHANNEL = "ai.awiki.awikime/document_picker"
        private const val UPDATE_CHANNEL = "ai.awiki.awikime/app_update"
        private const val REQUEST_SAVE_ZIP = 2001
        private const val REQUEST_PICK_ZIP = 2002
    }

    private var pendingSaveBytes: ByteArray? = null
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingPickResult: MethodChannel.Result? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQUEST_SAVE_ZIP -> handleSaveResult(resultCode = resultCode, data = data)
            REQUEST_PICK_ZIP -> handlePickResult(resultCode = resultCode, data = data)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOCUMENT_CHANNEL)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "saveZipFile" -> handleSaveZipFile(call = call, result = result)
                    "pickZipFile" -> launchPickDocument(result)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "canRequestPackageInstalls" -> result.success(canRequestPackageInstalls())
                    "openInstallPermissionSettings" -> {
                        try {
                            openInstallPermissionSettings()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("permission_settings_failed", formatExceptionMessage(e), null)
                        }
                    }
                    "installApk" -> handleInstallApk(call = call, result = result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleSaveZipFile(call: MethodCall, result: MethodChannel.Result) {
        try {
            val args = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
            val fileName = (args["file_name"] as? String)
                ?.takeIf { it.isNotBlank() }
                ?: throw IllegalArgumentException("file_name is required")
            val bytes = when (val raw = args["bytes"]) {
                is ByteArray -> raw
                is List<*> -> raw.filterIsInstance<Number>().map { it.toByte() }.toByteArray()
                else -> throw IllegalArgumentException("bytes is required")
            }
            launchSaveDocument(fileName = fileName, bytes = bytes, result = result)
        } catch (e: Exception) {
            result.error("save_failed", formatExceptionMessage(e), null)
        }
    }

    private fun handleInstallApk(call: MethodCall, result: MethodChannel.Result) {
        try {
            val args = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
            val filePath = (args["filePath"] as? String)
                ?.takeIf { it.isNotBlank() }
                ?: throw IllegalArgumentException("filePath is required")
            installApk(filePath)
            result.success(null)
        } catch (e: Exception) {
            result.error("apk_install_failed", formatExceptionMessage(e), null)
        }
    }

    private fun handleSaveResult(resultCode: Int, data: Intent?) {
        val callback = pendingSaveResult
        val bytes = pendingSaveBytes
        pendingSaveBytes = null
        pendingSaveResult = null
        if (callback == null) {
            return
        }
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            callback.success(null)
            return
        }
        val uri = data.data ?: return
        if (bytes == null) {
            callback.error("save_failed", "导出内容为空。", null)
            return
        }
        try {
            contentResolver.openOutputStream(uri)?.use { stream ->
                stream.write(bytes)
                stream.flush()
            } ?: throw IllegalStateException("无法打开目标文件。")
            callback.success(uri.toString())
        } catch (e: Exception) {
            callback.error("save_failed", formatExceptionMessage(e), null)
        }
    }

    private fun handlePickResult(resultCode: Int, data: Intent?) {
        val callback = pendingPickResult
        pendingPickResult = null
        if (callback == null) {
            return
        }
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            callback.success(null)
            return
        }
        val uri = data.data ?: return
        try {
            val bytes = contentResolver.openInputStream(uri)?.use { input ->
                input.readBytes()
            } ?: throw IllegalStateException("无法读取所选文件。")
            callback.success(bytes)
        } catch (e: Exception) {
            callback.error("pick_failed", formatExceptionMessage(e), null)
        }
    }

    private fun launchSaveDocument(
        fileName: String,
        bytes: ByteArray,
        result: MethodChannel.Result,
    ) {
        if (pendingSaveResult != null) {
            result.error("save_in_progress", "已有导出任务正在进行。", null)
            return
        }
        pendingSaveResult = result
        pendingSaveBytes = bytes
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/zip"
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        startActivityForResult(intent, REQUEST_SAVE_ZIP)
    }

    private fun launchPickDocument(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("pick_in_progress", "已有导入任务正在进行。", null)
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/zip"
        }
        startActivityForResult(intent, REQUEST_PICK_ZIP)
    }

    private fun canRequestPackageInstalls(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return true
        }
        return packageManager.canRequestPackageInstalls()
    }

    private fun openInstallPermissionSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName"),
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun installApk(filePath: String) {
        val apkFile = File(filePath)
        if (!apkFile.exists()) {
            throw IllegalArgumentException("APK file not found: $filePath")
        }
        val apkUri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            apkFile,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
    }

    private fun formatExceptionMessage(error: Throwable): String {
        val parts = mutableListOf<String>()
        var current: Throwable? = error
        while (current != null && parts.size < 5) {
            val message = current.message?.trim().takeUnless { it.isNullOrEmpty() }
                ?: current::class.java.simpleName
            if (parts.lastOrNull() != message) {
                parts.add(message)
            }
            current = current.cause
        }
        return parts.joinToString(" <- ")
    }
}
