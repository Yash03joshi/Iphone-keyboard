package expo.modules.hindiink.core

import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognition
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognitionModel
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognitionModelIdentifier
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognizer
import com.google.mlkit.vision.digitalink.recognition.DigitalInkRecognizerOptions
import com.google.mlkit.vision.digitalink.recognition.Ink
import com.google.mlkit.vision.digitalink.recognition.RecognitionContext
import com.google.mlkit.vision.digitalink.recognition.WritingArea

/**
 * Thin wrapper around ML Kit Digital Ink for Hindi (Devanagari).
 * Shared by the companion app and the keyboard (IME), which run in the same process,
 * so the downloaded model and the recognizer instance are shared too.
 * All callbacks are delivered on the main thread.
 */
object InkRecognizer {
  const val LANGUAGE_TAG = "hi"

  // ML Kit uses at most the last 20 characters of pre-context.
  private const val MAX_PRE_CONTEXT = 20

  private val model: DigitalInkRecognitionModel by lazy {
    val identifier = DigitalInkRecognitionModelIdentifier.fromLanguageTag(LANGUAGE_TAG)
      ?: error("ML Kit has no handwriting model for '$LANGUAGE_TAG'")
    DigitalInkRecognitionModel.builder(identifier).build()
  }

  private val modelManager: RemoteModelManager
    get() = RemoteModelManager.getInstance()

  private var recognizer: DigitalInkRecognizer? = null

  fun isModelDownloaded(callback: (Result<Boolean>) -> Unit) {
    modelManager.isModelDownloaded(model)
      .addOnSuccessListener { callback(Result.success(it)) }
      .addOnFailureListener { callback(Result.failure(it)) }
  }

  fun downloadModel(callback: (Result<Unit>) -> Unit) {
    modelManager.download(model, DownloadConditions.Builder().build())
      .addOnSuccessListener { callback(Result.success(Unit)) }
      .addOnFailureListener { callback(Result.failure(it)) }
  }

  fun deleteModel(callback: (Result<Unit>) -> Unit) {
    close()
    modelManager.deleteDownloadedModel(model)
      .addOnSuccessListener { callback(Result.success(Unit)) }
      .addOnFailureListener { callback(Result.failure(it)) }
  }

  /** Returns candidate texts, best first. Fails if the model is not downloaded. */
  fun recognize(
    ink: Ink,
    preContext: String,
    width: Float,
    height: Float,
    callback: (Result<List<String>>) -> Unit
  ) {
    if (ink.strokes.isEmpty()) {
      callback(Result.success(emptyList()))
      return
    }
    val context = RecognitionContext.builder()
      .setPreContext(preContext.takeLast(MAX_PRE_CONTEXT))
      .setWritingArea(WritingArea(width, height))
      .build()
    client().recognize(ink, context)
      .addOnSuccessListener { result -> callback(Result.success(result.candidates.map { it.text })) }
      .addOnFailureListener { callback(Result.failure(it)) }
  }

  /** Releases the loaded model from memory; it is reloaded on the next recognize(). */
  fun close() {
    recognizer?.close()
    recognizer = null
  }

  private fun client(): DigitalInkRecognizer =
    recognizer ?: DigitalInkRecognition.getClient(DigitalInkRecognizerOptions.builder(model).build())
      .also { recognizer = it }
}
