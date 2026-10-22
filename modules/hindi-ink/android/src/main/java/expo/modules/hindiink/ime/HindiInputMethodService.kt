package expo.modules.hindiink.ime

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.graphics.drawable.RippleDrawable
import android.inputmethodservice.InputMethodService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.WindowInsets
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import expo.modules.hindiink.R
import expo.modules.hindiink.core.HandwritingView
import expo.modules.hindiink.core.InkRecognizer

/**
 * The Hindi handwriting keyboard. Write a word, pause, and the best guess is typed with a
 * trailing space; the suggestion strip replaces that word with another guess.
 * Styled after Gboard: flat rounded keys, grey function keys, accent Enter, light/dark theme.
 */
class HindiInputMethodService : InputMethodService(), HandwritingView.Listener {
  private companion object {
    const val RECOGNIZE_DELAY_MS = 900L
    const val PRE_CONTEXT_LENGTH = 20
    const val REPEAT_START_MS = 400L
    const val REPEAT_INTERVAL_MS = 70L
    const val SUGGESTION_SLOTS = 3
    const val HINT = "Write here"
    const val KEY_HEIGHT_DP = 46

    // Gboard-style symbol pages; each has 3 rows above the shared bottom row.
    val SYMBOLS_1 = listOf("1234567890", "@#₹_&-+()/", "*\"':;!?")
    val SYMBOLS_2 = listOf("~`|•√π÷×।∆", "£¢€¥^°={}\\", "%©®™✓[]")

    // Marks that attach to the previous word: an auto-inserted space before them is removed.
    const val CLOSING_MARKS = ".,?!:;)]}%।"
  }

  private class Palette(
    val background: Int,
    val key: Int,
    val functionKey: Int,
    val keyShadow: Int,
    val text: Int,
    val muted: Int,
    val accent: Int,
    val onAccent: Int,
    val canvas: Int,
    val ink: Int,
    val chosen: Int,
    val divider: Int,
    val danger: Int,
    val ripple: Int,
  )

  private val lightPalette = Palette(
    background = 0xFFE8EAED.toInt(),
    key = 0xFFFFFFFF.toInt(),
    functionKey = 0xFFCDD1D6.toInt(),
    keyShadow = 0xFFB4B8BD.toInt(),
    text = 0xFF1F1F1F.toInt(),
    muted = 0xFF80868B.toInt(),
    accent = 0xFF0B57D0.toInt(),
    onAccent = 0xFFFFFFFF.toInt(),
    canvas = 0xFFF8F9FA.toInt(),
    ink = 0xFF111111.toInt(),
    chosen = 0xFFD3E3FD.toInt(),
    divider = 0xFFC4C7CC.toInt(),
    danger = 0xFFB3261E.toInt(),
    ripple = 0x33000000,
  )

  private val darkPalette = Palette(
    background = 0xFF202124.toInt(),
    key = 0xFF3C4043.toInt(),
    functionKey = 0xFF2D2E31.toInt(),
    keyShadow = 0xFF121212.toInt(),
    text = 0xFFE8EAED.toInt(),
    muted = 0xFF9AA0A6.toInt(),
    accent = 0xFF8AB4F8.toInt(),
    onAccent = 0xFF202124.toInt(),
    canvas = 0xFF2A2B2E.toInt(),
    ink = 0xFFF1F3F4.toInt(),
    chosen = 0xFF394457.toInt(),
    divider = 0xFF4A4D51.toInt(),
    danger = 0xFFF2B8B5.toInt(),
    ripple = 0x33FFFFFF,
  )

  private lateinit var palette: Palette

  private lateinit var canvas: HandwritingView
  private lateinit var hint: TextView
  private lateinit var writingPanel: View
  private lateinit var modelPanel: View
  private lateinit var modelMessage: TextView
  private lateinit var modelButton: View
  private lateinit var suggestionStrip: LinearLayout
  private lateinit var symbolPages: List<View>
  private lateinit var writeKeyRow: View
  private lateinit var symbolKeyRow: View

  /** 0 = handwriting, 1 = numbers & symbols, 2 = more symbols. */
  private var page = 0
  // null until ML Kit answers (can take a second on first use); assume ready meanwhile so the
  // download panel doesn't flash for the usual case.
  private var modelReady: Boolean? = null

  // The text typed by the last recognition (incl. any leading/trailing space), so a
  // suggestion tap can replace it. Cleared by any other edit.
  private var lastCommit: String? = null
  private var lastPrefix = ""
  private var lastCandidates: List<String> = emptyList()

  private var recognizing = false
  private var pausedWhileRecognizing = false

  private val handler = Handler(Looper.getMainLooper())

  // ---- Lifecycle ----

  override fun onCreateInputView(): View {
    val night = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
    palette = if (night == Configuration.UI_MODE_NIGHT_YES) darkPalette else lightPalette

    val root = LinearLayout(this).apply {
      orientation = LinearLayout.VERTICAL
      setBackgroundColor(palette.background)
    }
    root.setOnApplyWindowInsetsListener { view, insets ->
      // Keep the bottom row above the gesture/navigation bar on edge-to-edge devices.
      val bottom = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        insets.getInsets(WindowInsets.Type.navigationBars()).bottom
      } else {
        @Suppress("DEPRECATION")
        insets.systemWindowInsetBottom
      }
      view.setPadding(0, 0, 0, bottom)
      insets
    }

    suggestionStrip = LinearLayout(this).apply {
      orientation = LinearLayout.HORIZONTAL
      gravity = Gravity.CENTER_VERTICAL
      setPadding(dp(4), 0, dp(4), 0)
    }
    root.addView(suggestionStrip, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(48)))

    writingPanel = buildWritingPanel()
    modelPanel = buildModelPanel()
    val panelParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(220)).apply {
      setMargins(dp(6), 0, dp(6), dp(6))
    }
    root.addView(writingPanel, panelParams)
    root.addView(modelPanel, LinearLayout.LayoutParams(panelParams))
    symbolPages = listOf(buildSymbolPage(SYMBOLS_1, "=\\<", 2), buildSymbolPage(SYMBOLS_2, "?123", 1))
    // Symbol pages size to their keys (like Gboard), not to the taller writing area.
    symbolPages.forEach {
      root.addView(it, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
    }

    val rowParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(KEY_HEIGHT_DP)).apply {
      setMargins(dp(3), 0, dp(3), dp(8))
    }
    writeKeyRow = buildWriteRow()
    symbolKeyRow = buildSymbolRow()
    root.addView(writeKeyRow, rowParams)
    root.addView(symbolKeyRow, LinearLayout.LayoutParams(rowParams))
    showPage(0)
    return root
  }

  override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
    super.onStartInputView(info, restarting)
    canvas.clear()
    clearSuggestions()
    showPage(0)
    refreshModelState()
  }

  override fun onFinishInputView(finishingInput: Boolean) {
    canvas.clear()
    clearSuggestions()
    stopRepeat()
    super.onFinishInputView(finishingInput)
  }

  override fun onDestroy() {
    stopRepeat()
    InkRecognizer.close()
    super.onDestroy()
  }

  // ---- HandwritingView.Listener ----

  override fun onStrokesChanged(count: Int) {
    hint.visibility = if (count == 0) View.VISIBLE else View.GONE
  }

  override fun onWritingPaused() {
    if (recognizing) {
      pausedWhileRecognizing = true
      return
    }
    if (canvas.strokeCount == 0 || canvas.isWriting) return

    val strokeCount = canvas.strokeCount
    val preContext = currentInputConnection?.getTextBeforeCursor(PRE_CONTEXT_LENGTH, 0)?.toString().orEmpty()
    recognizing = true
    InkRecognizer.recognize(
      canvas.buildInk(),
      preContext,
      canvas.width.toFloat(),
      canvas.height.toFloat()
    ) { result ->
      recognizing = false
      result
        .onSuccess { candidates ->
          val words = candidates.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
          if (words.isNotEmpty()) commitRecognized(words)
          canvas.removeFirstStrokes(strokeCount)
        }
        .onFailure {
          setHint("Couldn't read that, please write again", palette.danger)
          canvas.clear()
          refreshModelState()
        }
      if (pausedWhileRecognizing) {
        pausedWhileRecognizing = false
        onWritingPaused()
      }
    }
  }

  // ---- Text editing ----

  private fun commitRecognized(words: List<String>) {
    val ic = currentInputConnection ?: return
    val before = ic.getTextBeforeCursor(1, 0)?.toString().orEmpty()
    // Separate from a word the user typed without a trailing space.
    lastPrefix = if (before.isNotEmpty() && !before.last().isWhitespace()) " " else ""
    val text = lastPrefix + words[0] + " "
    ic.commitText(text, 1)
    lastCommit = text
    lastCandidates = words.take(SUGGESTION_SLOTS)
    showSuggestions(0)
  }

  private fun chooseSuggestion(index: Int) {
    val ic = currentInputConnection ?: return
    val previous = lastCommit ?: return
    if (ic.getTextBeforeCursor(previous.length, 0)?.toString() != previous) {
      // The text changed since we typed it (cursor moved, user edited); don't clobber it.
      clearSuggestions()
      return
    }
    val text = lastPrefix + lastCandidates[index] + " "
    ic.beginBatchEdit()
    ic.deleteSurroundingText(previous.length, 0)
    ic.commitText(text, 1)
    ic.endBatchEdit()
    lastCommit = text
    showSuggestions(index)
  }

  /** Removes the last stroke if there is unrecognized ink, otherwise deletes text. */
  private fun backspace() {
    if (canvas.strokeCount > 0) {
      canvas.undoStroke()
      return
    }
    clearSuggestions()
    sendDownUpKeyEvents(KeyEvent.KEYCODE_DEL)
  }

  private fun typeSymbol(symbol: String) {
    val ic = currentInputConnection ?: return
    // Right after a recognized word: "नमस्ते ," → "नमस्ते, " (keep the space after the mark).
    val attach = lastCommit != null && symbol in CLOSING_MARKS &&
      ic.getTextBeforeCursor(1, 0)?.toString() == " "
    clearSuggestions()
    if (attach) {
      ic.beginBatchEdit()
      ic.deleteSurroundingText(1, 0)
      ic.commitText("$symbol ", 1)
      ic.endBatchEdit()
    } else {
      ic.commitText(symbol, 1)
    }
  }

  private fun typeSpace() {
    clearSuggestions()
    currentInputConnection?.commitText(" ", 1)
  }

  private fun enter() {
    clearSuggestions()
    val ic = currentInputConnection ?: return
    val options = currentInputEditorInfo?.imeOptions ?: 0
    val action = options and EditorInfo.IME_MASK_ACTION
    val hasAction = options and EditorInfo.IME_FLAG_NO_ENTER_ACTION == 0 &&
      action != EditorInfo.IME_ACTION_NONE &&
      action != EditorInfo.IME_ACTION_UNSPECIFIED
    if (hasAction) ic.performEditorAction(action) else sendKeyChar('\n')
  }

  private fun showKeyboardPicker() {
    (getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager).showInputMethodPicker()
  }

  // ---- Model state ----

  private fun refreshModelState() {
    InkRecognizer.isModelDownloaded { result ->
      modelReady = result.getOrDefault(false)
      if (modelReady == true) setHint(HINT, palette.muted)
      showPage(page)
    }
  }

  /** Switches between handwriting (0) and the symbol pages (1, 2). */
  private fun showPage(newPage: Int) {
    if (newPage != 0 && page == 0) canvas.clear()
    page = newPage
    fun visibleIf(condition: Boolean) = if (condition) View.VISIBLE else View.GONE
    writingPanel.visibility = visibleIf(page == 0 && modelReady != false)
    modelPanel.visibility = visibleIf(page == 0 && modelReady == false)
    symbolPages.forEachIndexed { index, view -> view.visibility = visibleIf(page == index + 1) }
    writeKeyRow.visibility = visibleIf(page == 0)
    symbolKeyRow.visibility = visibleIf(page != 0)
  }

  private fun downloadModel() {
    modelMessage.text = "Downloading… please wait."
    modelButton.isEnabled = false
    modelButton.alpha = 0.5f
    InkRecognizer.downloadModel { result ->
      modelButton.isEnabled = true
      modelButton.alpha = 1f
      result
        .onSuccess { refreshModelState() }
        .onFailure { modelMessage.text = "Download failed. Turn on the internet and try again." }
    }
  }

  // ---- Views ----

  private fun buildWritingPanel(): View {
    val frame = FrameLayout(this).apply {
      background = rounded(palette.canvas, radius = 12)
      clipToOutline = true
    }
    canvas = HandwritingView(this).also {
      it.pauseDelayMs = RECOGNIZE_DELAY_MS
      it.inkColor = palette.ink
      it.listener = this
    }
    frame.addView(canvas, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    hint = TextView(this).apply {
      setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
      gravity = Gravity.CENTER
    }
    setHint(HINT, palette.muted)
    frame.addView(hint, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER))
    return frame
  }

  private fun buildModelPanel(): View {
    val panel = LinearLayout(this).apply {
      orientation = LinearLayout.VERTICAL
      gravity = Gravity.CENTER
      background = rounded(palette.canvas, radius = 12)
      setPadding(dp(16), dp(16), dp(16), dp(16))
      visibility = View.GONE
    }
    modelMessage = TextView(this).apply {
      text = "Hindi recognition needs a one-time download (about 20 MB)."
      setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
      setTextColor(palette.text)
      gravity = Gravity.CENTER
    }
    panel.addView(modelMessage)
    modelButton = textKey("Download", palette.accent, palette.onAccent, sizeSp = 18f) { downloadModel() }
      .apply { setPadding(dp(28), 0, dp(28), 0) }
    panel.addView(
      modelButton,
      LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(48)).apply { topMargin = dp(16) }
    )
    return panel
  }

  private fun keyRow(vararg keys: Pair<View, Float>): LinearLayout {
    val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
    for ((view, weight) in keys) {
      row.addView(view, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, weight).apply {
        setMargins(dp(3), 0, dp(3), 0)
      })
    }
    return row
  }

  private fun buildWriteRow(): View = keyRow(
    textKey("?123", palette.functionKey, palette.text, sizeSp = 16f) { showPage(1) } to 1.4f,
    iconKey(R.drawable.hindi_ink_ic_globe, "Switch keyboard", palette.functionKey, palette.text) { showKeyboardPicker() } to 1.2f,
    textKey(",", palette.functionKey, palette.text) { typeSymbol(",") } to 1f,
    spaceKey() to 4f,
    deleteKey() to 1.5f,
    enterKey() to 1.5f,
  )

  private fun buildSymbolRow(): View = keyRow(
    textKey("अ", palette.functionKey, palette.text, sizeSp = 20f) { showPage(0) }
      .apply { contentDescription = "Handwriting" } to 1.4f,
    textKey(",", palette.functionKey, palette.text) { typeSymbol(",") } to 1f,
    spaceKey() to 4.2f,
    textKey(".", palette.functionKey, palette.text) { typeSymbol(".") } to 1f,
    enterKey() to 1.5f,
  )

  /** Three rows of symbol keys; the last row starts with a page switch and ends with delete. */
  private fun buildSymbolPage(rows: List<String>, switchLabel: String, switchTo: Int): View {
    val page = LinearLayout(this).apply {
      orientation = LinearLayout.VERTICAL
      visibility = View.GONE
    }
    fun symbolKeys(chars: String) = chars.map { char ->
      val symbol = char.toString()
      textKey(symbol, palette.key, palette.text, bold = false) { typeSymbol(symbol) } to 1f
    }
    val rowViews = listOf(
      keyRow(*symbolKeys(rows[0]).toTypedArray()),
      keyRow(*symbolKeys(rows[1]).toTypedArray()),
      keyRow(
        textKey(switchLabel, palette.functionKey, palette.text, sizeSp = 16f) { showPage(switchTo) } to 1.5f,
        *symbolKeys(rows[2]).toTypedArray(),
        deleteKey() to 1.5f,
      ),
    )
    rowViews.forEach {
      page.addView(it, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(KEY_HEIGHT_DP)).apply {
        setMargins(dp(3), 0, dp(3), dp(10))
      })
    }
    return page
  }

  private fun spaceKey(): View =
    textKey("Space", palette.key, palette.muted, sizeSp = 16f, bold = false) { typeSpace() }

  private fun enterKey(): View =
    iconKey(R.drawable.hindi_ink_ic_enter, "Enter", palette.accent, palette.onAccent) { enter() }

  /** Delete key that repeats while held. */
  @SuppressLint("ClickableViewAccessibility")
  private fun deleteKey(): View {
    val delete = iconKey(R.drawable.hindi_ink_ic_backspace, "Delete", palette.functionKey, palette.text) {}
    delete.setOnTouchListener { view, event ->
      when (event.actionMasked) {
        MotionEvent.ACTION_DOWN -> {
          view.isPressed = true
          view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
          backspace()
          startRepeat()
        }
        MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
          view.isPressed = false
          stopRepeat()
        }
      }
      true
    }
    return delete
  }

  private val repeatDelete = object : Runnable {
    override fun run() {
      // Only repeat-delete typed text; never wipe the user's ink in one long press.
      if (canvas.strokeCount > 0) return
      backspace()
      handler.postDelayed(this, REPEAT_INTERVAL_MS)
    }
  }

  private fun startRepeat() {
    handler.postDelayed(repeatDelete, REPEAT_START_MS)
  }

  private fun stopRepeat() {
    handler.removeCallbacks(repeatDelete)
  }

  /** Gboard-style strip: equal slots split by thin dividers, the word in the text highlighted. */
  private fun showSuggestions(chosen: Int) {
    suggestionStrip.removeAllViews()
    lastCandidates.forEachIndexed { index, word ->
      if (index > 0) {
        suggestionStrip.addView(
          View(this).apply { setBackgroundColor(palette.divider) },
          LinearLayout.LayoutParams(dp(1), dp(24))
        )
      }
      val slot = TextView(this).apply {
        text = word
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
        setTextColor(palette.text)
        typeface = if (index == chosen) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        gravity = Gravity.CENTER
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
        contentDescription = word
        val fill = if (index == chosen) palette.chosen else palette.background
        background = RippleDrawable(ColorStateList.valueOf(palette.ripple), rounded(fill, radius = 20), null)
        isClickable = true
        setOnClickListener {
          it.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
          chooseSuggestion(index)
        }
      }
      suggestionStrip.addView(
        slot,
        LinearLayout.LayoutParams(0, dp(40), 1f).apply { setMargins(dp(4), 0, dp(4), 0) }
      )
    }
  }

  private fun clearSuggestions() {
    lastCommit = null
    lastCandidates = emptyList()
    if (::suggestionStrip.isInitialized) suggestionStrip.removeAllViews()
  }

  private fun setHint(text: String, color: Int) {
    hint.text = text
    hint.setTextColor(color)
  }

  private fun textKey(
    label: String,
    color: Int,
    textColor: Int,
    sizeSp: Float = 22f,
    bold: Boolean = true,
    onClick: () -> Unit
  ): TextView = TextView(this).apply {
    text = label
    setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
    setTextColor(textColor)
    typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
    gravity = Gravity.CENTER
    contentDescription = label
    background = keyBackground(color)
    isClickable = true
    setOnClickListener {
      it.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
      onClick()
    }
  }

  private fun iconKey(
    icon: Int,
    description: String,
    color: Int,
    tint: Int,
    onClick: () -> Unit
  ): View = FrameLayout(this).apply {
    contentDescription = description
    background = keyBackground(color)
    isClickable = true
    setOnClickListener {
      it.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
      onClick()
    }
    addView(
      ImageView(context).apply {
        setImageResource(icon)
        imageTintList = ColorStateList.valueOf(tint)
      },
      FrameLayout.LayoutParams(dp(24), dp(24), Gravity.CENTER)
    )
  }

  /** Rounded key with a 1dp shadow along the bottom edge, plus a press ripple. */
  private fun keyBackground(color: Int): Drawable {
    val layers = LayerDrawable(arrayOf(rounded(palette.keyShadow), rounded(color)))
    layers.setLayerInset(1, 0, 0, 0, dp(1))
    return RippleDrawable(ColorStateList.valueOf(palette.ripple), layers, null)
  }

  private fun rounded(color: Int, radius: Int = 8) = GradientDrawable().apply {
    setColor(color)
    cornerRadius = dp(radius).toFloat()
  }

  private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
