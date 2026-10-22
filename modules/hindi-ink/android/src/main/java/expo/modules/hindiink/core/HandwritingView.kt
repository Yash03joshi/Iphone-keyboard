package expo.modules.hindiink.core

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import com.google.mlkit.vision.digitalink.recognition.Ink

/**
 * Plain Android view that captures finger strokes, draws them, and builds an ML Kit [Ink].
 * Independent of React Native so the keyboard (IME) can use it directly.
 */
class HandwritingView(context: Context) : View(context) {
  interface Listener {
    fun onStrokesChanged(count: Int)

    /** Called once the user has stopped writing for [pauseDelayMs]. */
    fun onWritingPaused()
  }

  var listener: Listener? = null

  /** Delay after the last stroke before [Listener.onWritingPaused]; 0 disables it. */
  var pauseDelayMs: Long = 0

  var strokeWidthPx: Float
    get() = inkPaint.strokeWidth
    set(value) {
      inkPaint.strokeWidth = value
      invalidate()
    }

  var inkColor: Int
    get() = inkPaint.color
    set(value) {
      inkPaint.color = value
      invalidate()
    }

  val strokeCount: Int
    get() = strokes.size

  /** True while a finger is down mid-stroke. */
  val isWriting: Boolean
    get() = current != null

  private class Stroke {
    val path = Path()
    val points = ArrayList<Ink.Point>()
  }

  private val strokes = ArrayList<Stroke>()
  private var current: Stroke? = null

  private val inkPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    color = Color.BLACK
    style = Paint.Style.STROKE
    strokeCap = Paint.Cap.ROUND
    strokeJoin = Paint.Join.ROUND
    strokeWidth = 6f * resources.displayMetrics.density
  }

  private val handler = Handler(Looper.getMainLooper())
  private val pauseCallback = Runnable { listener?.onWritingPaused() }

  fun buildInk(): Ink {
    val builder = Ink.builder()
    for (stroke in strokes) {
      val strokeBuilder = Ink.Stroke.builder()
      stroke.points.forEach(strokeBuilder::addPoint)
      builder.addStroke(strokeBuilder.build())
    }
    return builder.build()
  }

  fun clear() {
    handler.removeCallbacks(pauseCallback)
    strokes.clear()
    current = null
    invalidate()
    listener?.onStrokesChanged(0)
  }

  /**
   * Removes the oldest [count] strokes, e.g. the ones just recognized, while keeping any
   * strokes written while recognition was running.
   */
  fun removeFirstStrokes(count: Int) {
    if (count >= strokes.size) {
      clear()
      return
    }
    strokes.subList(0, count).clear()
    invalidate()
    listener?.onStrokesChanged(strokes.size)
  }

  fun undoStroke() {
    if (strokes.isEmpty()) return
    handler.removeCallbacks(pauseCallback)
    strokes.removeAt(strokes.lastIndex)
    invalidate()
    listener?.onStrokesChanged(strokes.size)
    schedulePause()
  }

  @SuppressLint("ClickableViewAccessibility")
  override fun onTouchEvent(event: MotionEvent): Boolean {
    when (event.actionMasked) {
      MotionEvent.ACTION_DOWN -> {
        // Keep scroll views / sheets from stealing the gesture while writing.
        parent?.requestDisallowInterceptTouchEvent(true)
        handler.removeCallbacks(pauseCallback)
        val stroke = Stroke()
        stroke.path.moveTo(event.x, event.y)
        stroke.points.add(point(event.x, event.y, event.eventTime))
        strokes.add(stroke)
        current = stroke
        invalidate()
      }
      MotionEvent.ACTION_MOVE -> {
        val stroke = current ?: return true
        for (i in 0 until event.historySize) {
          addPoint(stroke, event.getHistoricalX(i), event.getHistoricalY(i), event.getHistoricalEventTime(i))
        }
        addPoint(stroke, event.x, event.y, event.eventTime)
        invalidate()
      }
      MotionEvent.ACTION_UP -> {
        val stroke = current ?: return true
        addPoint(stroke, event.x, event.y, event.eventTime)
        current = null
        invalidate()
        listener?.onStrokesChanged(strokes.size)
        schedulePause()
      }
      MotionEvent.ACTION_CANCEL -> {
        current?.let { strokes.remove(it) }
        current = null
        invalidate()
      }
    }
    return true
  }

  override fun onDraw(canvas: Canvas) {
    super.onDraw(canvas)
    for (stroke in strokes) {
      canvas.drawPath(stroke.path, inkPaint)
    }
  }

  override fun onDetachedFromWindow() {
    handler.removeCallbacks(pauseCallback)
    super.onDetachedFromWindow()
  }

  private fun addPoint(stroke: Stroke, x: Float, y: Float, uptimeMs: Long) {
    // A single tap is still a valid stroke (e.g. a dot); lineTo keeps the path drawable.
    stroke.path.lineTo(x, y)
    stroke.points.add(point(x, y, uptimeMs))
  }

  // ML Kit expects wall-clock timestamps; MotionEvent times are uptime-based.
  private fun point(x: Float, y: Float, uptimeMs: Long): Ink.Point {
    val wallMs = System.currentTimeMillis() - (android.os.SystemClock.uptimeMillis() - uptimeMs)
    return Ink.Point.create(x, y, wallMs)
  }

  private fun schedulePause() {
    if (pauseDelayMs > 0 && strokes.isNotEmpty()) {
      handler.postDelayed(pauseCallback, pauseDelayMs)
    }
  }
}
