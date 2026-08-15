package com.theohowie.linkstudy.overlay

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.WindowManager
import com.theohowie.linkstudy.MainActivity
import com.theohowie.linkstudy.R

/**
 * 悬浮窗前台服务（开发文档 §5.1）：
 * - startForegroundService + 常驻通知（通知渠道 linkstudy_overlay）；
 * - 负责悬浮球（OverlayView）的创建/移动/移除；
 * - 支持点击（事件上报 + 拉起 App）、拖放接收（ACTION_DROP 提取 URL）、
 *   剪贴板导入（拉前台后读取，改造项 A1）。
 */
class OverlayService : Service() {
    private lateinit var windowManager: WindowManager
    private var overlayView: OverlayView? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var panelView: OverlayPanelView? = null
    private var panelParams: WindowManager.LayoutParams? = null
    private val handler = Handler(Looper.getMainLooper())
    private var style: String = OverlayView.DEFAULT_STYLE
    private var opacity: Float = 1f
    private var panelColors: Map<*, *>? = null

    companion object {
        private const val CHANNEL_ID = "linkstudy_overlay"
        private const val NOTIFICATION_ID = 1001

        /** 当前运行的服务实例（供 MethodChannel 调用实例方法）。 */
        var instance: OverlayService? = null
            private set

        fun start(context: Context) {
            val intent = Intent(context, OverlayService::class.java).apply {
                action = ACTION_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, OverlayService::class.java))
        }

        fun isOverlayPermissionGranted(context: Context): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

        fun openPermissionSettings(context: Context) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${context.packageName}")
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }

        /** 点击"粘贴"：把 App 拉至前台后读取剪贴板（后台读剪贴板受系统限制）。 */
        @SuppressLint("ServiceCast")
        fun requestClipboardImport(context: Context) {
            bringAppToFront(context)
            // 等 Activity 可见后读取，规避前台限制
            Handler(Looper.getMainLooper()).postDelayed({
                val cm = context.getSystemService(Context.CLIPBOARD_SERVICE)
                        as? android.content.ClipboardManager
                val text = cm?.primaryClip?.takeIf { it.itemCount > 0 }
                    ?.getItemAt(0)?.coerceToText(context)?.toString()
                val urls = OverlayChannel.extractUrls(text)
                OverlayChannel.sendUrls(urls, "clipboard")
            }, 500)
        }

        fun bringAppToFront(context: Context) {
            val intent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            context.startActivity(intent)
        }

        private const val ACTION_START = "com.theohowie.linkstudy.overlay.START"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        if (intent?.action == ACTION_START || overlayView == null) {
            showOverlay()
        }
        return START_STICKY
    }

    /** 切换悬浮球样式（由 MethodChannel 调用，即时刷新）。 */
    fun applyStyle(newStyle: String) {
        style = newStyle
        overlayView?.let { v ->
            v.applyStyle(newStyle)
            layoutParams?.let { p ->
                val (w, h) = overlaySizePx(newStyle)
                p.width = w
                p.height = h
                runCatching { windowManager.updateViewLayout(v, p) }
            }
        }
    }

    /** 设置悬浮球透明度（0-100，由 MethodChannel 调用）。 */
    fun applyOpacity(opacityPercent: Int) {
        opacity = (opacityPercent.coerceIn(20, 100) / 100f)
        overlayView?.alpha = opacity
    }

    /** 应用 Material 3 主题色到填写面板（由 MethodChannel 调用）。 */
    fun applyPanelColors(colors: Map<*, *>?) {
        panelColors = colors
        panelView?.updateColors(colors)
    }

    /** 悬浮球窗口尺寸（px），按样式计算，不依赖 view.layoutParams。 */
    private fun overlaySizePx(s: String): Pair<Int, Int> {
        val density = resources.displayMetrics.density
        return if (s == OverlayView.STYLE_BALL_WHITE) {
            Pair((40 * density).toInt(), (40 * density).toInt())
        } else {
            Pair((72 * density).toInt(), (30 * density).toInt())
        }
    }

    override fun onDestroy() {
        instance = null
        removeOverlay()
        super.onDestroy()
    }

    private fun showOverlay() {
        if (overlayView != null) return
        if (!isOverlayPermissionGranted(this)) return

        val view = OverlayView(this).apply { applyStyle(style) }
        val (vw, vh) = overlaySizePx(style)
        val dm = resources.displayMetrics
        val params = WindowManager.LayoutParams(
            vw,
            vh,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_PHONE,
            // 允许覆盖状态栏区域：LAYOUT_IN_SCREEN + LAYOUT_NO_LIMITS
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            // API 30+：不避开任何系统栏 inset，允许窗口延伸到状态栏
            if (Build.VERSION.SDK_INT >= 30) {
                setFitInsetsTypes(0)
            }
            // gravity=TOP|START：x 相对屏幕左边缘，支持全屏自由拖动
            gravity = Gravity.TOP or Gravity.START
            // 默认位置：顶部水平居中（灵动岛/挖孔位），y = 状态栏高度 + 8dp
            x = ((dm.widthPixels - vw) / 2).coerceAtLeast(0)
            y = statusBarHeight() + dp(8)
        }

        view.onTapCallback = {
            // 点击悬浮球：展开/收起填写面板（不跳转前台）
            if (panelView != null) hidePanel() else showPanel()
        }
        view.onUrlsCallback = { urls ->
            OverlayChannel.sendUrls(urls, "drag")
        }
        view.onMoveCallback = { dx, dy ->
            layoutParams?.let { p ->
                val dm = resources.displayMetrics
                p.x = (p.x + dx.toInt()).coerceIn(0, (dm.widthPixels - p.width).coerceAtLeast(0))
                p.y = (p.y + dy.toInt()).coerceIn(0, (dm.heightPixels - p.height).coerceAtLeast(0))
                windowManager.updateViewLayout(view, p)
            }
        }

        overlayView = view
        layoutParams = params
        windowManager.addView(view, params)
    }

    private fun removeOverlay() {
        hidePanel()
        overlayView?.let { v ->
            runCatching { windowManager.removeView(v) }
            overlayView = null
            layoutParams = null
        }
    }

    /** 在屏幕中上部展开填写面板（可聚焦，支持软键盘）。 */
    private fun showPanel() {
        if (panelView != null) return
        val panel = OverlayPanelView(this, panelColors)
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = statusBarHeight() + dp(120)
            // 允许输入法调整，避免键盘遮挡
            softInputMode = android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
            horizontalMargin = dp(12).toFloat()
        }

        panel.onSave = { url, title, duration, priority, deadlineDay ->
            OverlayChannel.sendDraftSaved(url, title, duration, priority, deadlineDay)
            hidePanel()
        }
        panel.onCancel = { hidePanel() }

        panelView = panel
        panelParams = params
        runCatching { windowManager.addView(panel, params) }
    }

    private fun hidePanel() {
        panelView?.let { p ->
            runCatching { windowManager.removeView(p) }
            panelView = null
            panelParams = null
        }
    }

    private fun statusBarHeight(): Int {
        val id = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) runCatching { resources.getDimensionPixelSize(id) }.getOrDefault(0) else 0
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    private fun buildNotification(): Notification {
        val tapIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("LinkStudy 采集已就绪")
            .setContentText("把网课链接拖给悬浮窗，或复制后点悬浮窗\"粘贴\"")
            .setContentIntent(tapIntent)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "悬浮窗采集",
                NotificationManager.IMPORTANCE_LOW,
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
