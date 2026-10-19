package studio.cue.cue

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.Activity
import android.content.Intent
import java.io.File

class MainActivity : FlutterActivity() {
    private var exportResult: MethodChannel.Result? = null
    private var exportFile: File? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "studio.cue/export").setMethodCallHandler { call, result ->
            if (call.method != "exportRecording") { result.notImplemented(); return@setMethodCallHandler }
            val path = call.argument<String>("path")
            val file = path?.let { File(it) }
            if (file == null || !file.exists() || !file.canonicalPath.startsWith(File(applicationInfo.dataDir).canonicalPath + "/") || exportResult != null) {
                result.error("unavailable", "Recording cannot be exported right now.", null); return@setMethodCallHandler
            }
            exportResult = result; exportFile = file
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "audio/wav"
                putExtra(Intent.EXTRA_TITLE, File(call.argument<String>("name") ?: "CUE.wav").name)
            }
            try { startActivityForResult(intent, 7721) }
            catch (error: Exception) { exportResult = null; exportFile = null; result.error("export", "No file export application is available.", null) }
        }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 7721) return
        val result = exportResult ?: return
        val file = exportFile
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || file == null || uri == null) {
            exportResult = null; exportFile = null; result.success(false); return
        }
        Thread {
            try {
                val output = contentResolver.openOutputStream(uri) ?: throw IllegalStateException("Export destination is unavailable.")
                output.use { stream -> file.inputStream().use { it.copyTo(stream) } }
                runOnUiThread { exportResult = null; exportFile = null; result.success(true) }
            } catch (error: Exception) {
                runOnUiThread { exportResult = null; exportFile = null; result.error("export", "Recording could not be saved: ${error.message}", null) }
            }
        }.start()
    }
}
