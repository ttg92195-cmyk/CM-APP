package than.pre.cm

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.content.ContentResolver
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.cmmovies/saf_storage"
    private val REQUEST_CODE_OPEN_TREE = 1001
    private var pendingResult: MethodChannel.Result? = null
    private var selectedTreeUri: Uri? = null

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openFolderPicker" -> {
                    pendingResult = result
                    openFolderPicker()
                }
                "saveFileToFolder" -> {
                    val treeUri = call.argument<String>("treeUri") ?: ""
                    val sourceFilePath = call.argument<String>("sourceFilePath") ?: ""
                    val fileName = call.argument<String>("fileName") ?: ""
                    val saved = saveFileToFolder(treeUri, sourceFilePath, fileName)
                    result.success(saved)
                }
                "fileExistsInFolder" -> {
                    val treeUri = call.argument<String>("treeUri") ?: ""
                    val fileName = call.argument<String>("fileName") ?: ""
                    val exists = fileExistsInFolder(treeUri, fileName)
                    result.success(exists)
                }
                "deleteFileFromFolder" -> {
                    val treeUri = call.argument<String>("treeUri") ?: ""
                    val fileName = call.argument<String>("fileName") ?: ""
                    val deleted = deleteFileFromFolder(treeUri, fileName)
                    result.success(deleted)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun openFolderPicker() {
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                )
            }
            startActivityForResult(intent, REQUEST_CODE_OPEN_TREE)
        } catch (e: Exception) {
            pendingResult?.error("SAF_ERROR", "Failed to open folder picker: ${e.message}", null)
            pendingResult = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == REQUEST_CODE_OPEN_TREE) {
            if (resultCode == RESULT_OK && data != null) {
                val treeUri = data.data
                if (treeUri != null) {
                    selectedTreeUri = treeUri

                    // Take persistable URI permission
                    try {
                        contentResolver.takePersistableUriPermission(
                            treeUri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                        )
                    } catch (e: Exception) {
                        // Some devices don't support persistable permissions for all URIs
                    }

                    // Get human-readable path
                    val treePath = getTreePath(treeUri)

                    pendingResult?.success(mapOf(
                        "treeUri" to treeUri.toString(),
                        "treePath" to treePath
                    ))
                } else {
                    pendingResult?.success(null)
                }
            } else {
                // User cancelled
                pendingResult?.success(null)
            }
            pendingResult = null
        }
    }

    /**
     * Convert a SAF tree URI to a human-readable file path.
     * e.g. content://com.android.externalstorage.documents/tree/primary%3ADownload
     *      -> /storage/emulated/0/Download
     */
    private fun getTreePath(treeUri: Uri): String {
        try {
            // Handle ExternalStorageProvider URIs
            if (treeUri.toString().contains("com.android.externalstorage.documents")) {
                val docId = DocumentsContract.getTreeDocumentId(treeUri)
                // docId format: "primary:Download" or "1234-5678:Movies"
                val parts = docId.split(":")
                if (parts.size >= 2) {
                    val volume = parts[0]
                    val path = parts[1]
                    val basePath = when (volume) {
                        "primary" -> "/storage/emulated/0"
                        else -> "/storage/$volume"
                    }
                    return "$basePath/$path"
                } else if (parts.size == 1) {
                    // Whole storage
                    val volume = parts[0]
                    return when (volume) {
                        "primary" -> "/storage/emulated/0"
                        else -> "/storage/$volume"
                    }
                }
            }
        } catch (e: Exception) {
            // Fall through
        }

        // Fallback: try to get path from the URI directly
        val decoded = Uri.decode(treeUri.toString())
        // Try to extract a readable name from the URI
        val lastSegment = treeUri.lastPathSegment ?: "Selected Folder"
        return lastSegment.replace(":", "/").replace("primary", "/storage/emulated/0")
    }

    /**
     * Save a file from a local path to the SAF folder.
     * This copies the file using ContentResolver so it works with scoped storage.
     */
    private fun saveFileToFolder(treeUriStr: String, sourceFilePath: String, fileName: String): Boolean {
        try {
            val treeUri = Uri.parse(treeUriStr)
            val sourceFile = java.io.File(sourceFilePath)
            if (!sourceFile.exists()) return false

            // Get the document ID of the tree
            val treeDocId = DocumentsContract.getTreeDocumentId(treeUri)
            val treeDocUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, treeDocId)

            // Check if file already exists and delete it
            deleteFileFromFolder(treeUriStr, fileName)

            // Create the new file
            val mimeType = getMimeType(fileName)
            val newFileUri = DocumentsContract.createDocument(
                contentResolver,
                treeDocUri,
                mimeType,
                fileName
            ) ?: return false

            // Copy the content
            contentResolver.openOutputStream(newFileUri)?.use { outputStream ->
                java.io.FileInputStream(sourceFile).use { inputStream ->
                    val buffer = ByteArray(8192)
                    var bytesRead: Int
                    while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                        outputStream.write(buffer, 0, bytesRead)
                    }
                    outputStream.flush()
                }
            }

            return true
        } catch (e: Exception) {
            android.util.Log.e("SafStorage", "saveFileToFolder error: ${e.message}")
            return false
        }
    }

    /**
     * Check if a file exists in the SAF folder
     */
    private fun fileExistsInFolder(treeUriStr: String, fileName: String): Boolean {
        try {
            val treeUri = Uri.parse(treeUriStr)
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                DocumentsContract.getTreeDocumentId(treeUri)
            )

            contentResolver.query(
                childrenUri,
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, OpenableColumns.DISPLAY_NAME),
                null, null, null
            )?.use { cursor ->
                val nameColumn = cursor.getColumnIndexOrThrow(OpenableColumns.DISPLAY_NAME)
                while (cursor.moveToNext()) {
                    val name = cursor.getString(nameColumn)
                    if (name == fileName) return true
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("SafStorage", "fileExistsInFolder error: ${e.message}")
        }
        return false
    }

    /**
     * Delete a file from the SAF folder
     */
    private fun deleteFileFromFolder(treeUriStr: String, fileName: String): Boolean {
        try {
            val treeUri = Uri.parse(treeUriStr)
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                DocumentsContract.getTreeDocumentId(treeUri)
            )

            contentResolver.query(
                childrenUri,
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, OpenableColumns.DISPLAY_NAME),
                null, null, null
            )?.use { cursor ->
                val docIdColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameColumn = cursor.getColumnIndexOrThrow(OpenableColumns.DISPLAY_NAME)
                while (cursor.moveToNext()) {
                    val name = cursor.getString(nameColumn)
                    if (name == fileName) {
                        val docId = cursor.getString(docIdColumn)
                        val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                        return DocumentsContract.deleteDocument(contentResolver, docUri)
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("SafStorage", "deleteFileFromFolder error: ${e.message}")
        }
        return false
    }

    /**
     * Get MIME type from file name
     */
    private fun getMimeType(fileName: String): String {
        val extension = fileName.substringAfterLast('.', "").lowercase()
        return when (extension) {
            "mp4" -> "video/mp4"
            "mkv" -> "video/x-matroska"
            "avi" -> "video/x-msvideo"
            "webm" -> "video/webm"
            "mov" -> "video/quicktime"
            "wmv" -> "video/x-ms-wmv"
            "flv" -> "video/x-flv"
            "m4v" -> "video/mp4"
            "ts" -> "video/mp2t"
            "zip" -> "application/zip"
            "rar" -> "application/x-rar-compressed"
            "7z" -> "application/x-7z-compressed"
            else -> MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "application/octet-stream"
        }
    }
}
