package com.theohowie.linkstudy.overlay

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

/** 悬浮填写面板的 Material 3 主题色（由 Flutter 经 MethodChannel 下发）。 */
class PanelColors(map: Map<*, *>?) {
    val primary: Int = colorOf(map, "primary", 0xFF0A56C4.toInt())
    val onPrimary: Int = colorOf(map, "onPrimary", 0xFFFFFFFF.toInt())
    val surface: Int = colorOf(map, "surface", 0xFFFFFFFF.toInt())
    val onSurface: Int = colorOf(map, "onSurface", 0xFF1A1C1E.toInt())
    val onSurfaceVariant: Int = colorOf(map, "onSurfaceVariant", 0xFF44474E.toInt())
    val outline: Int = colorOf(map, "outline", 0xFF74777F.toInt())

    private fun colorOf(map: Map<*, *>?, key: String, fallback: Int): Int {
        val raw = map?.get(key)
        return if (raw is Number) raw.toInt() else fallback
    }
}

/**
 * 悬浮填写面板（点击悬浮球在下方展开，不跳转前台）。
 *
 * 字段：链接（可粘贴）、名称、时长；按钮：粘贴链接 / 保存 / 取消。
 * 样式跟随 Flutter 下发的 Material 3 主题色（PanelColors）；保存后经 EventChannel 上报 onDraftSaved。
 */
class OverlayPanelView(context: Context, colors: Map<*, *>?) : LinearLayout(context) {

    /** 保存回调：url / title / durationMinutes / priority(high|medium|low) / deadlineDay(epochDay，可空)。 */
    var onSave: ((String, String, Int, String, Long?) -> Unit)? = null
    var onCancel: (() -> Unit)? = null

    private var theme = PanelColors(colors)

    private var priority = "medium"
    private var deadlineDay: Long? = null

    private val urlInput = EditText(context)
    private val titleInput = EditText(context)
    private val durationInput = EditText(context)
    private val urlUnderline = View(context)
    private val titleUnderline = View(context)
    private val durationUnderline = View(context)
    private val priorityButton = Button(context)
    private val deadlineButton = Button(context)
    private val pasteButton = Button(context)
    private val saveButton = Button(context)
    private val cancelButton = Button(context)

    init {
        orientation = VERTICAL
        setPadding(dp(20), dp(16), dp(20), dp(16))
        background = GradientDrawable().apply {
            cornerRadius = dp(16).toFloat()
            setColor(theme.surface)
            setStroke(dp(1), theme.outline)
        }

        addView(TextView(context).apply {
            text = "添加课程"
            textSize = 17f
            setTextColor(theme.onSurface)
            typeface = Typeface.DEFAULT_BOLD
        })

        addView(
            buildInputRow(urlInput, urlUnderline, "链接 URL（可粘贴）", InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI),
            inputRowParams(),
        )
        addView(
            buildInputRow(titleInput, titleUnderline, "课程名称", InputType.TYPE_CLASS_TEXT),
            inputRowParams(),
        )
        addView(
            buildInputRow(durationInput, durationUnderline, "时长（分钟）", InputType.TYPE_CLASS_NUMBER),
            inputRowParams(),
        )
        addView(
            buildInlineButton(priorityButton, "优先级：中") {
                priority = when (priority) {
                    "high" -> "medium"
                    "medium" -> "low"
                    else -> "high"
                }
                priorityButton.text = "优先级：${priorityLabel(priority)}"
            },
            inputRowParams(),
        )
        addView(
            buildInlineButton(deadlineButton, "截止日期：无") { pickDeadline() },
            inputRowParams(),
        )

        val row = LinearLayout(context).apply { orientation = HORIZONTAL }
        pasteButton.apply {
            text = "粘贴链接"
            background = null
            setTextColor(theme.primary)
            setOnClickListener { pasteFromClipboard() }
        }
        row.addView(pasteButton, buttonParams())
        cancelButton.apply {
            text = "取消"
            background = null
            setTextColor(theme.onSurfaceVariant)
            setOnClickListener { onCancel?.invoke() }
        }
        row.addView(cancelButton, buttonParams())
        saveButton.apply {
            text = "保存"
            background = filledButtonBackground()
            setTextColor(theme.onPrimary)
            setOnClickListener { save() }
        }
        row.addView(saveButton, buttonParams())
        addView(row, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(14)
            gravity = Gravity.END
        })
    }

    private fun buildInlineButton(button: Button, text: String, onClick: () -> Unit): Button {
        return button.apply {
            this.text = text
            background = null
            setTextColor(theme.primary)
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
            setPadding(0, dp(6), 0, dp(6))
            setOnClickListener { onClick() }
        }
    }

    private fun priorityLabel(p: String): String = when (p) {
        "high" -> "高"
        "medium" -> "中"
        else -> "低"
    }

    private fun pickDeadline() {
        val now = java.util.Calendar.getInstance()
        android.app.DatePickerDialog(
            context,
            { _, y, m, d ->
                val cal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC")).apply {
                    clear()
                    set(y, m, d)
                }
                deadlineDay = cal.timeInMillis / 86400000L
                deadlineButton.text = "截止日期：$y-${(m + 1).toString().padStart(2, '0')}-${d.toString().padStart(2, '0')}"
            },
            now.get(java.util.Calendar.YEAR),
            now.get(java.util.Calendar.MONTH),
            now.get(java.util.Calendar.DAY_OF_MONTH),
        ).show()
    }

    private fun buildInputRow(
        input: EditText,
        underline: View,
        hint: String,
        inputType: Int,
    ): LinearLayout {
        input.apply {
            this.hint = hint
            this.inputType = inputType
            setTextColor(theme.onSurface)
            setHintTextColor(theme.onSurfaceVariant)
            background = null
            setPadding(dp(2), dp(8), dp(2), dp(6))
            imeOptions = EditorInfo.IME_ACTION_DONE
        }
        underline.apply {
            setBackgroundColor(theme.outline)
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, dp(1))
        }
        input.setOnFocusChangeListener { _, hasFocus ->
            underline.setBackgroundColor(if (hasFocus) theme.primary else theme.outline)
        }
        val column = LinearLayout(context).apply { orientation = VERTICAL }
        column.addView(input)
        column.addView(underline)
        return column
    }

    private fun filledButtonBackground() = GradientDrawable().apply {
        cornerRadius = dp(20).toFloat()
        setColor(theme.primary)
    }

    /** 面板已显示时刷新主题色（明暗切换/自定义色）。 */
    fun updateColors(map: Map<*, *>?) {
        theme = PanelColors(map)
        (background as? GradientDrawable)?.setColor(theme.surface)
        urlInput.setTextColor(theme.onSurface)
        urlInput.setHintTextColor(theme.onSurfaceVariant)
        titleInput.setTextColor(theme.onSurface)
        titleInput.setHintTextColor(theme.onSurfaceVariant)
        durationInput.setTextColor(theme.onSurface)
        durationInput.setHintTextColor(theme.onSurfaceVariant)
        urlUnderline.setBackgroundColor(if (urlInput.hasFocus()) theme.primary else theme.outline)
        titleUnderline.setBackgroundColor(if (titleInput.hasFocus()) theme.primary else theme.outline)
        durationUnderline.setBackgroundColor(if (durationInput.hasFocus()) theme.primary else theme.outline)
        priorityButton.setTextColor(theme.primary)
        deadlineButton.setTextColor(theme.primary)
        pasteButton.setTextColor(theme.primary)
        cancelButton.setTextColor(theme.onSurfaceVariant)
        saveButton.setTextColor(theme.onPrimary)
        (saveButton.background as? GradientDrawable)?.setColor(theme.primary)
    }

    private fun inputRowParams() = LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
        topMargin = dp(10)
    }

    private fun buttonParams() = LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
        marginStart = dp(4)
    }

    private fun pasteFromClipboard() {
        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
        val text = cm.primaryClip
            ?.takeIf { it.itemCount > 0 }
            ?.getItemAt(0)
            ?.coerceToText(context)
            ?.toString()
        if (text.isNullOrBlank()) {
            Toast.makeText(context, "剪贴板为空，请先复制链接", Toast.LENGTH_SHORT).show()
            return
        }
        val urls = OverlayChannel.extractUrls(text)
        urlInput.setText(if (urls.isNotEmpty()) urls.first() else text.trim())
        if (titleInput.text.isBlank()) {
            titleInput.setText(extractTitleHint(text))
        }
    }

    /** 从文本/URL 提取标题提示（路径最后一段或 host）。 */
    private fun extractTitleHint(text: String): String {
        val uri = android.net.Uri.parse(text.trim())
        val segments = uri.pathSegments?.filter { it.isNotEmpty() && it.length > 3 }
        return segments?.lastOrNull() ?: (uri.host ?: "")
    }

    private fun save() {
        val url = urlInput.text.toString().trim()
        val title = titleInput.text.toString().trim()
        val duration = durationInput.text.toString().trim().toIntOrNull()

        if (OverlayChannel.extractUrls(url).isEmpty() && !url.startsWith("http")) {
            Toast.makeText(context, "请输入合法的 http(s) 链接", Toast.LENGTH_SHORT).show()
            return
        }
        if (title.isEmpty()) {
            Toast.makeText(context, "请输入课程名称", Toast.LENGTH_SHORT).show()
            return
        }
        if (duration == null || duration < 1 || duration > 600) {
            Toast.makeText(context, "时长需为 1-600 的整数（分钟）", Toast.LENGTH_SHORT).show()
            return
        }
        onSave?.invoke(url, title, duration, priority, deadlineDay)
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()
}
