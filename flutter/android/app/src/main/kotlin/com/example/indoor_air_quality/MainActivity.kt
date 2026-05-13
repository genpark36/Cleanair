package com.example.indoor_air_quality

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val csvChannel = "cleanair/csv"
    private val systemChannel = "cleanair/system"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, csvChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveCsvToDownloads") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val fileName = call.argument<String>("fileName")
                val csvContent = call.argument<String>("csvContent")
                if (fileName.isNullOrBlank() || csvContent == null) {
                    result.error("invalid_args", "CSV fileName or content is empty.", null)
                    return@setMethodCallHandler
                }

                try {
                    val path = saveCsvToDownloads(fileName, csvContent)
                    result.success(path)
                } catch (error: Exception) {
                    result.error("csv_save_failed", error.message, null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "openDialer") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val number = call.argument<String>("number") ?: "119"
                try {
                    val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number"))
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                } catch (error: Exception) {
                    result.error("dialer_failed", error.message, null)
                }
            }
    }

    private fun saveCsvToDownloads(fileName: String, csvContent: String): String {
        val folderName = "AirGradient"
        val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/$folderName"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, "text/csv")
                put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Download provider returned null URI.")

            resolver.openOutputStream(uri)?.use { stream ->
                stream.write(csvContent.toByteArray(Charsets.UTF_8))
            } ?: throw IllegalStateException("Could not open CSV output stream.")

            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return "Download/$folderName/$fileName"
        }

        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            folderName
        )
        if (!dir.exists()) dir.mkdirs()
        val file = File(dir, fileName)
        file.writeText(csvContent, Charsets.UTF_8)
        return file.absolutePath
    }
}
