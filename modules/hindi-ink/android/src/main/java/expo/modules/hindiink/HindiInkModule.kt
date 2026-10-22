package expo.modules.hindiink

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import expo.modules.hindiink.core.InkRecognizer
import expo.modules.kotlin.exception.Exceptions
import expo.modules.kotlin.Promise
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class HindiInkModule : Module() {
  private val context: Context
    get() = appContext.reactContext ?: throw Exceptions.ReactContextLost()

  private val inputMethodManager: InputMethodManager
    get() = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager

  override fun definition() = ModuleDefinition {
    Name("HindiInk")

    AsyncFunction("isModelDownloaded") { promise: Promise ->
      InkRecognizer.isModelDownloaded { result ->
        result.onSuccess(promise::resolve).onFailure { promise.reject("ERR_MODEL_STATUS", it.message, it) }
      }
    }

    AsyncFunction("downloadModel") { promise: Promise ->
      InkRecognizer.downloadModel { result ->
        result.onSuccess { promise.resolve(null) }.onFailure { promise.reject("ERR_MODEL_DOWNLOAD", it.message, it) }
      }
    }

    AsyncFunction("deleteModel") { promise: Promise ->
      InkRecognizer.deleteModel { result ->
        result.onSuccess { promise.resolve(null) }.onFailure { promise.reject("ERR_MODEL_DELETE", it.message, it) }
      }
    }

    Function("getKeyboardStatus") {
      val packageName = context.packageName
      val enabled = inputMethodManager.enabledInputMethodList.any { it.packageName == packageName }
      val current = Settings.Secure.getString(context.contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)
      val selected = current?.let { ComponentName.unflattenFromString(it)?.packageName } == packageName
      mapOf("enabled" to enabled, "selected" to selected)
    }

    Function("openKeyboardSettings") {
      context.startActivity(
        Intent(Settings.ACTION_INPUT_METHOD_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      )
    }

    Function("showKeyboardPicker") {
      inputMethodManager.showInputMethodPicker()
    }

    View(HindiInkView::class) {
      Events("onStrokesChange", "onRecognized", "onRecognitionError")

      Prop("strokeWidth") { view: HindiInkView, width: Float ->
        view.canvas.strokeWidthPx = width * view.resources.displayMetrics.density
      }

      Prop("recognizeDelayMs") { view: HindiInkView, delay: Int ->
        view.canvas.pauseDelayMs = delay.toLong()
      }

      Prop("preContext") { view: HindiInkView, text: String ->
        view.preContext = text
      }

      AsyncFunction("clear") { view: HindiInkView ->
        view.canvas.clear()
      }

      AsyncFunction("undo") { view: HindiInkView ->
        view.canvas.undoStroke()
      }

      AsyncFunction("recognize") { view: HindiInkView, promise: Promise ->
        view.recognize { result ->
          result.onSuccess(promise::resolve).onFailure { promise.reject("ERR_RECOGNIZE", it.message, it) }
        }
      }
    }
  }
}
