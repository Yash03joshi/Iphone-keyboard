package expo.modules.hindiink

import android.content.Context
import expo.modules.hindiink.core.HandwritingView
import expo.modules.hindiink.core.InkRecognizer
import expo.modules.kotlin.AppContext
import expo.modules.kotlin.viewevent.EventDispatcher
import expo.modules.kotlin.views.ExpoView

/** React Native wrapper around [HandwritingView] for the companion app's practice screen. */
class HindiInkView(context: Context, appContext: AppContext) : ExpoView(context, appContext) {
  override val shouldUseAndroidLayout = true

  private val onStrokesChange by EventDispatcher()
  private val onRecognized by EventDispatcher()
  private val onRecognitionError by EventDispatcher()

  var preContext: String = ""

  val canvas = HandwritingView(context).also {
    it.layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
    addView(it)
  }

  init {
    canvas.listener = object : HandwritingView.Listener {
      override fun onStrokesChanged(count: Int) {
        onStrokesChange(mapOf("count" to count))
      }

      override fun onWritingPaused() {
        recognize { result ->
          result
            .onSuccess { onRecognized(mapOf("candidates" to it)) }
            .onFailure { onRecognitionError(mapOf("message" to (it.message ?: it.toString()))) }
        }
      }
    }
  }

  fun recognize(callback: (Result<List<String>>) -> Unit) {
    InkRecognizer.recognize(
      canvas.buildInk(),
      preContext,
      canvas.width.toFloat(),
      canvas.height.toFloat(),
      callback
    )
  }
}
