package com.example.whereis

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 엑셀 파일을 스마트폰에서 바로 볼 수 있는 '다운로드' 폴더에 저장하고,
 * '다운로드' 폴더에서 시작하는 파일 선택 창을 띄우기 위한 네이티브 코드.
 *
 * 저장소 권한이 필요 없도록 MediaStore(Android 10+)와 SAF를 사용한다.
 */
class MainActivity : FlutterActivity() {
    private var pendingPickResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> saveToDownloads(call, result)
                    "pickFile" -> pickFile(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    /** 엑셀 바이트를 '다운로드' 폴더에 저장하고 실제 파일 경로를 돌려준다. */
    private fun saveToDownloads(call: MethodCall, result: MethodChannel.Result) {
        val name = call.argument<String>("name")
        val bytes = call.argument<ByteArray>("bytes")
        if (name.isNullOrEmpty() || bytes == null) {
            result.error("bad_arguments", "name과 bytes가 필요합니다", null)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            // Android 10 미만은 저장소 권한이 필요하므로 직접 저장하지 않고
            // 시스템 저장 대화상자(SAF)로 넘긴다.
            result.error("unsupported", "Android 10 미만은 지원하지 않습니다", null)
            return
        }
        try {
            result.success(writeToDownloads(name, bytes))
        } catch (e: Exception) {
            result.error("save_failed", e.message ?: e.toString(), null)
        }
    }

    private fun writeToDownloads(name: String, bytes: ByteArray): String {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeTypeFor(name))
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
        }
        val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("다운로드 폴더에 파일을 만들 수 없습니다")
        try {
            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("다운로드 폴더에 파일을 쓸 수 없습니다")
        } catch (e: Exception) {
            contentResolver.delete(uri, null, null)
            throw e
        }
        val savedName = displayName(uri) ?: name
        val dir =
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        return File(dir, savedName).absolutePath
    }

    /** '다운로드' 폴더에서 시작하는 파일 선택 창을 연다. */
    private fun pickFile(call: MethodCall, result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("already_active", "이미 파일 선택이 진행 중입니다", null)
            return
        }
        val types = call.argument<List<String>>("mimeTypes")
            ?.filter { it.isNotBlank() }
            .orEmpty()
        val primaryType = types.firstOrNull() ?: "*/*"
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = primaryType
            if (types.size > 1) {
                putExtra(Intent.EXTRA_MIME_TYPES, types.toTypedArray())
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(DOWNLOADS_ROOT_URI))
            }
        }
        if (intent.resolveActivity(packageManager) == null) {
            result.error("no_picker", "파일 선택 앱을 찾을 수 없습니다", null)
            return
        }
        pendingPickResult = result
        startActivityForResult(intent, PICK_REQUEST_CODE)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_REQUEST_CODE) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingPickResult ?: return
        pendingPickResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null) // 사용자가 취소
            return
        }
        try {
            val name = displayName(uri) ?: DEFAULT_FILE_NAME
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: throw IllegalStateException("파일을 읽을 수 없습니다")
            val picked = HashMap<String, Any?>()
            picked["name"] = name
            picked["bytes"] = bytes
            picked["location"] = uri.toString()
            result.success(picked)
        } catch (e: Exception) {
            result.error("read_failed", e.message ?: e.toString(), null)
        }
    }

    /** 저장할 파일 이름의 확장자에 맞는 MIME 형식을 돌려준다. */
    private fun mimeTypeFor(name: String): String =
        when (name.substringAfterLast('.', "").lowercase()) {
            "zip" -> ZIP_MIME
            "xls" -> LEGACY_XLS_MIME
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            else -> XLSX_MIME
        }

    private fun displayName(uri: Uri): String? {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) return cursor.getString(index)
                }
            }
        return null
    }

    companion object {
        private const val CHANNEL = "udiso/files"
        private const val PICK_REQUEST_CODE = 49321
        private const val XLSX_MIME =
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        private const val LEGACY_XLS_MIME = "application/vnd.ms-excel"
        private const val ZIP_MIME = "application/zip"
        private const val DEFAULT_FILE_NAME = "file"

        /** 안드로이드 파일 선택 창의 '다운로드' 폴더 문서 URI */
        private const val DOWNLOADS_ROOT_URI =
            "content://com.android.providers.downloads.documents/root/downloads"
    }
}
