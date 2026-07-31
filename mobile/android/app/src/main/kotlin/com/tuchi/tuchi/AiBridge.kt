package com.tuchi.tuchi

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import android.util.Log
import androidx.exifinterface.media.ExifInterface
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.ImagePart
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Cầu nối on-device AI cho Flutter (channel "tuchi/ai"):
 * - OCR text: ML Kit Text Recognition (lớp 0 — regex/heuristic chạy trên text này)
 * - Gemini Nano: ML Kit GenAI Prompt API qua AICore (lớp 1)
 * - Gemma 3n: LiteRT-LM từ file .litertlm (lớp 2 — thiết bị không có AICore)
 */
class AiBridge(private val context: Context) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private val nanoModel: GenerativeModel by lazy { Generation.getClient() }

    private var gemmaEngine: Engine? = null
    private var gemmaEnginePath: String? = null
    private var gemmaHasVision = false
    private val gemmaMutex = Mutex()

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            scope.launch {
                try {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    when (call.method) {
                        "ocrText" -> result.success(ocrText(args["imagePath"] as String))
                        "nanoStatus" -> result.success(nanoStatus())
                        "nanoDownload" -> result.success(nanoDownload())
                        "nanoGenerate" -> result.success(
                            nanoGenerate(args["prompt"] as String, args["imagePath"] as? String)
                        )
                        "gemmaAvailable" -> result.success(gemmaAvailable(args["modelPath"] as String))
                        "gemmaGenerate" -> result.success(
                            gemmaGenerate(
                                args["prompt"] as String,
                                args["imagePath"] as? String,
                                args["modelPath"] as String,
                            )
                        )
                        "gemmaUnload" -> {
                            unloadGemma()
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Method ${call.method} failed", e)
                    result.error("ai_error", e.message ?: e.toString(), null)
                }
            }
        }
    }

    // ---------- ML Kit Text Recognition (OCR text cho lớp 0) ----------

    private suspend fun ocrText(imagePath: String): String = withContext(Dispatchers.IO) {
        val image = InputImage.fromFilePath(context, Uri.fromFile(File(imagePath)))
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        try {
            recognizer.process(image).await().text
        } finally {
            recognizer.close()
        }
    }

    // ---------- Gemini Nano (ML Kit GenAI Prompt API) ----------

    private suspend fun nanoStatus(): String = withContext(Dispatchers.IO) {
        try {
            when (nanoModel.checkStatus()) {
                FeatureStatus.AVAILABLE -> "available"
                FeatureStatus.DOWNLOADABLE -> "downloadable"
                FeatureStatus.DOWNLOADING -> "downloading"
                else -> "unavailable"
            }
        } catch (e: Exception) {
            Log.w(TAG, "nanoStatus failed: ${e.message}")
            "unavailable"
        }
    }

    private suspend fun nanoDownload(): String = withContext(Dispatchers.IO) {
        try {
            nanoModel.download()
            "completed"
        } catch (e: Exception) {
            throw IllegalStateException("Tải Gemini Nano thất bại: ${e.message}")
        }
    }

    private suspend fun nanoGenerate(prompt: String, imagePath: String?): String =
        withContext(Dispatchers.IO) {
            val response = if (imagePath != null) {
                val bitmap = loadBitmap(imagePath)
                nanoModel.generateContent(
                    generateContentRequest(ImagePart(bitmap), TextPart(prompt)) {
                        temperature = 0.1f
                        topK = 16
                        candidateCount = 1
                    },
                )
            } else {
                nanoModel.generateContent(
                    generateContentRequest(TextPart(prompt)) {
                        temperature = 0.1f
                        topK = 16
                        candidateCount = 1
                    },
                )
            }
            response.candidates.firstOrNull()?.text
                ?: throw IllegalStateException("Gemini Nano không trả kết quả")
        }

    // ---------- Gemma 3n (LiteRT-LM) ----------

    private fun gemmaAvailable(modelPath: String): Boolean {
        val f = File(modelPath)
        // File model thật luôn > 100MB; tránh nhận file tải dở
        return f.exists() && f.length() > 100L * 1024 * 1024
    }

    private suspend fun gemmaGenerate(prompt: String, imagePath: String?, modelPath: String): String =
        withContext(Dispatchers.IO) {
            val engine = gemmaMutex.withLock { ensureGemmaEngine(modelPath) }
            engine.createConversation().use { conversation ->
                val message = if (imagePath != null && gemmaHasVision) {
                    conversation.sendMessage(
                        Contents.of(Content.ImageFile(imagePath), Content.Text(prompt))
                    )
                } else {
                    conversation.sendMessage(prompt)
                }
                message.toString()
            }
        }

    private fun ensureGemmaEngine(modelPath: String): Engine {
        gemmaEngine?.let {
            if (gemmaEnginePath == modelPath) return it
            runCatching { it.close() }
            gemmaEngine = null
        }
        if (!gemmaAvailable(modelPath)) {
            throw IllegalStateException("Chưa có file model Gemma tại $modelPath")
        }

        // Thử lần lượt: GPU + vision → CPU + vision → CPU text-only
        val attempts: List<Pair<EngineConfig, Boolean>> = listOf(
            EngineConfig(
                modelPath = modelPath,
                backend = Backend.GPU(),
                visionBackend = Backend.GPU(),
                cacheDir = context.cacheDir.path,
            ) to true,
            EngineConfig(
                modelPath = modelPath,
                backend = Backend.CPU(),
                visionBackend = Backend.CPU(),
                cacheDir = context.cacheDir.path,
            ) to true,
            EngineConfig(
                modelPath = modelPath,
                backend = Backend.CPU(),
                cacheDir = context.cacheDir.path,
            ) to false,
        )

        var lastError: Exception? = null
        for ((config, hasVision) in attempts) {
            try {
                val engine = Engine(config)
                engine.initialize()
                gemmaEngine = engine
                gemmaEnginePath = modelPath
                gemmaHasVision = hasVision
                return engine
            } catch (e: Exception) {
                Log.w(TAG, "Gemma engine init failed (${config.backend}): ${e.message}")
                lastError = e
            }
        }
        throw IllegalStateException("Không khởi tạo được Gemma: ${lastError?.message}")
    }

    private fun unloadGemma() {
        runCatching { gemmaEngine?.close() }
        gemmaEngine = null
        gemmaEnginePath = null
    }

    // ---------- Helpers ----------

    /** Đọc ảnh, xoay đúng chiều theo EXIF và thu nhỏ để tiết kiệm token/RAM. */
    private fun loadBitmap(path: String, maxDim: Int = 1280): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        var sample = 1
        while (bounds.outWidth / sample > maxDim * 2 || bounds.outHeight / sample > maxDim * 2) {
            sample *= 2
        }
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        var bitmap = BitmapFactory.decodeFile(path, opts)
            ?: throw IllegalArgumentException("Không đọc được ảnh $path")

        val w = bitmap.width
        val h = bitmap.height
        if (w > maxDim || h > maxDim) {
            val scale = maxDim.toFloat() / maxOf(w, h)
            bitmap = Bitmap.createScaledBitmap(bitmap, (w * scale).toInt(), (h * scale).toInt(), true)
        }

        val rotation = when (
            ExifInterface(path).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        ) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> 0f
        }
        if (rotation != 0f) {
            val matrix = Matrix().apply { postRotate(rotation) }
            bitmap = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        }
        return bitmap
    }

    companion object {
        private const val TAG = "TuchiAiBridge"
        const val CHANNEL = "tuchi/ai"
    }
}
