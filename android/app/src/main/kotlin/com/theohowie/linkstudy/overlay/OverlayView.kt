package com.theohowie.linkstudy.overlay

import android.content.ClipData
import android.content.ClipDescription
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.DragEvent
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.TextView

/**
 * 悬浮球视图（可移动 + 双样式 + 无文字）。
 *
 * 样式：
 * - "capsule_black"：黑色圆角胶囊（默认），宽 72dp 高 30dp，纯色无文字；
 * - "ball_white"：白色圆球，直径 40dp，纯色无文字。
 *
 * 交互：
 * - 拖动（onTouch 更新位置，经 onMoveCallback 交给服务更新 WindowManager）；
 * - 点击（ACTION_UP 未移动时 performClick → onTapCallback，服务展开填写面板）；
 * - 拖放接收（OnDragListener 的 ACTION_DROP 提取文本中的 URL）。
 */
class OverlayView(context: Context) : TextView(context) {

    var onTapCallback: (() -> Unit)? = null
    var onUrlsCallback: ((List<String>) -> Unit)? = null
    var onMoveCallback: ((Float, Float) -> Unit)? = null

    private var downX = 0f
    private var downY = 0f
    private var moved = false

    private val bg = GradientDrawable()
    private var style = DEFAULT_STYLE

    companion object {
        const val STYLE_CAPSULE_BLACK = "capsule_black"
        const val STYLE_BALL_WHITE = "ball_white"
        const val DEFAULT_STYLE = STYLE_CAPSULE_BLACK
    }

    init {
        text = ""
        background = bg

        setOnClickListener { onTapCallback?.invoke() }

        setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downX
                    val dy = event.rawY - downY
                    if (kotlin.math.abs(dx) > 8 || kotlin.math.abs(dy) > 8) {
                        moved = true
                        onMoveCallback?.invoke(dx, dy)
                        downX = event.rawX
                        downY = event.rawY
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) {
                        performClick()
                    }
                    true
                }
                else -> false
            }
        }

        setOnDragListener { _, event ->
            when (event.action) {
                DragEvent.ACTION_DRAG_STARTED -> {
                    if (event.clipDescription?.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN) == true) {
                        highlight(true)
                        true
                    } else {
                        false
                    }
                }
                DragEvent.ACTION_DROP -> {
                    highlight(false)
                    val text = extractText(event.clipData)
                    val urls = OverlayChannel.extractUrls(text)
                    if (urls.isNotEmpty()) {
                        onUrlsCallback?.invoke(urls)
                    }
                    true
                }
                DragEvent.ACTION_DRAG_ENDED -> {
                    highlight(false)
                    true
                }
                else -> true
            }
        }
    }

    /** 应用样式：仅刷新外观（尺寸由 OverlayService 统一管理，避免 layoutParams 传递问题）。 */
    fun applyStyle(newStyle: String) {
        style = newStyle
        drawShape()
    }

    private fun drawShape() {
        bg.mutate()
        when (style) {
            STYLE_BALL_WHITE -> {
                bg.shape = GradientDrawable.OVAL
                bg.setColor(Color.WHITE)
                bg.setStroke(dp(2), Color.rgb(200, 200, 200))
            }
            else -> {
                bg.shape = GradientDrawable.RECTANGLE
                bg.cornerRadius = dp(15).toFloat()
                bg.setColor(Color.rgb(20, 20, 20))
            }
        }
        background = bg
        invalidate()
    }

    private fun highlight(on: Boolean) {
        bg.mutate()
        bg.setColor(if (on) Color.rgb(255, 152, 0) else if (style == STYLE_BALL_WHITE) Color.WHITE else Color.rgb(20, 20, 20))
        invalidate()
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    private fun extractText(clip: ClipData?): String? {
        if (clip == null) return null
        for (i in 0 until clip.itemCount) {
            val item = clip.getItemAt(i)
            val text = item.coerceToText(context)?.toString()
            if (!text.isNullOrBlank()) return text
        }
        return null
    }
}
