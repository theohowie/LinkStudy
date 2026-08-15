package com.theohowie.linkstudy.overlay

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.regex.Pattern
import com.theohowie.linkstudy.MainActivity

/**
 * 悬浮窗平台通道（开发文档 §6）：
 * - MethodChannel "com.theohowie.linkstudy.overlay"：start/stop/permission/settings/clipboard
 * - EventChannel "com.theohowie.linkstudy.overlay/events"：onUrlsCaptured / onOverlayTapped / onDraftSaved
 */
object OverlayChannel {
    const val METHOD = "com.theohowie.linkstudy.overlay"
    const val EVENTS = "com.theohowie.linkstudy.overlay/events"

    private var method: MethodChannel? = null
    private var events: EventChannel? = null
    private var sink: EventChannel.EventSink? = null

    /** 由 MainActivity.onCreate 注入，用于权限请求与 context。 */
    var appContext: android.content.Context? = null
    var mainActivity: MainActivity? = null

    private val urlPattern: Pattern =
        Pattern.compile("https?://[^\\s<>\"')\\]}，。；！？]+")

    /** 由 MainActivity.configureFlutterEngine 调用。 */
    fun attach(messenger: BinaryMessenger) {
        method = MethodChannel(messenger, METHOD).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "startOverlay" -> {
                        OverlayService.start(applicationContext())
                        result.success(null)
                    }
                    "stopOverlay" -> {
                        OverlayService.stop(applicationContext())
                        result.success(null)
                    }
                    "isOverlayPermissionGranted" ->
                        result.success(OverlayService.isOverlayPermissionGranted(applicationContext()))
                    "openOverlayPermissionSettings" -> {
                        OverlayService.openPermissionSettings(applicationContext())
                        result.success(null)
                    }
                    "requestClipboardImport" -> {
                        OverlayService.requestClipboardImport(applicationContext())
                        result.success(null)
                    }
                    "requestNotificationPermission" -> {
                        requestNotificationPermission()
                        result.success(null)
                    }
                    "setOverlayStyle" -> {
                        val s = call.argument<String>("style") ?: OverlayView.DEFAULT_STYLE
                        OverlayService.instance?.applyStyle(s)
                        result.success(null)
                    }
                    "setOverlayOpacity" -> {
                        val o = call.argument<Int>("opacity") ?: 100
                        OverlayService.instance?.applyOpacity(o)
                        result.success(null)
                    }
                    "setPanelColors" -> {
                        OverlayService.instance?.applyPanelColors(call.arguments as? Map<*, *>)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        events = EventChannel(messenger, EVENTS).apply {
            setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sink = events
                }

                override fun onCancel(arguments: Any?) {
                    sink = null
                }
            })
        }
    }

    /** 从一段文本中提取全部 URL。 */
    fun extractUrls(text: String?): List<String> {
        if (text.isNullOrBlank()) return emptyList()
        val matcher = urlPattern.matcher(text)
        val out = LinkedHashSet<String>()
        while (matcher.find()) {
            out.add(matcher.group().trimEnd('.', ',', ';', ':', '!', '?'))
        }
        return out.toList()
    }

    /** 上报采集到的 URL（拖放 / 剪贴板）。 */
    fun sendUrls(urls: List<String>, source: String) {
        if (urls.isEmpty()) return
        sink?.success(mapOf("type" to "onUrlsCaptured", "urls" to urls, "source" to source))
    }

    /** 悬浮面板保存课程草稿（url/title/duration/priority/deadlineDay）。 */
    fun sendDraftSaved(url: String, title: String, durationMinutes: Int, priority: String, deadlineDay: Long?) {
        sink?.success(mapOf(
            "type" to "onDraftSaved",
            "url" to url,
            "title" to title,
            "durationMinutes" to durationMinutes,
            "priority" to priority,
            "deadlineDay" to deadlineDay,
        ))
    }

    /** 用户点击悬浮球。 */
    fun sendTapped() {
        sink?.success(mapOf("type" to "onOverlayTapped"))
    }

    /** Android 13+ 通知权限运行时申请（前台服务通知必需）。 */
    private fun requestNotificationPermission() {
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            mainActivity?.requestPermissions(
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                1001,
            )
        }
    }

    private fun applicationContext(): android.content.Context =
        requireNotNull(appContext) { "OverlayChannel.appContext 未注入（应由 MainActivity.onCreate 赋值）" }
}
