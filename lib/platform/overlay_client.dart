import 'dart:async';

import 'package:flutter/services.dart';

/// 悬浮球样式值（与原生 OverlayView 对应）。
const overlayStyleCapsuleBlack = 'capsule_black';
const overlayStyleBallWhite = 'ball_white';

/// 悬浮窗设置持久化键（SharedPreferences）。
const overlayPrefsEnabledKey = 'overlay_enabled';
const overlayPrefsStyleKey = 'overlay_style';
const overlayPrefsOpacityKey = 'overlay_opacity';

/// 悬浮面板保存的课程草稿。
class DraftSaved {
  final String url;
  final String title;
  final int durationMinutes;

  const DraftSaved({
    required this.url,
    required this.title,
    required this.durationMinutes,
  });
}

/// 悬浮窗原生通道封装（MethodChannel + EventChannel）。
/// 通道定义见开发文档 §6（LinkStudy 移植）。
class OverlayClient {
  static const _method = MethodChannel('com.theohowie.linkstudy.overlay');
  static const _events = EventChannel('com.theohowie.linkstudy.overlay/events');

  Future<bool> isPermissionGranted() async =>
      (await _method.invokeMethod<bool>('isOverlayPermissionGranted')) ?? false;

  Future<void> startOverlay() => _method.invokeMethod('startOverlay');

  Future<void> stopOverlay() => _method.invokeMethod('stopOverlay');

  Future<void> openPermissionSettings() =>
      _method.invokeMethod('openOverlayPermissionSettings');

  /// 点击悬浮窗"粘贴"：原生将 App 拉至前台读取剪贴板，随后回调 capturedUrls。
  Future<void> requestClipboardImport() =>
      _method.invokeMethod('requestClipboardImport');

  /// Android 13+ 通知权限运行时申请（前台服务通知必需）。
  Future<void> requestNotificationPermission() =>
      _method.invokeMethod('requestNotificationPermission');

  /// 切换悬浮球样式：capsule_black（黑色胶囊）| ball_white（白色圆球）。
  Future<void> setOverlayStyle(String style) =>
      _method.invokeMethod('setOverlayStyle', {'style': style});

  /// 设置悬浮球透明度（20-100）。
  Future<void> setOverlayOpacity(int opacity) =>
      _method.invokeMethod('setOverlayOpacity', {'opacity': opacity});

  /// 下发 Material 3 主题色给原生填写面板（key: primary/onPrimary/surface/onSurface/onSurfaceVariant/outline）。
  Future<void> setPanelColors(Map<String, int> colors) =>
      _method.invokeMethod('setPanelColors', colors);

  /// 采集事件流：拖放 / 剪贴板导入的 URL 列表。
  Stream<List<String>> get capturedUrls => _events
      .receiveBroadcastStream()
      .where((e) => e is Map && e['type'] == 'onUrlsCaptured')
      .map((e) => List<String>.from((e as Map)['urls'] as List));

  /// 用户点击悬浮球（Flutter 决定展开确认卡/队列）。
  Stream<void> get overlayTapped => _events
      .receiveBroadcastStream()
      .where((e) => e is Map && e['type'] == 'onOverlayTapped')
      .map((_) {});

  /// 悬浮面板保存课程草稿（url/title/durationMinutes）。
  Stream<DraftSaved> get draftsSaved => _events
      .receiveBroadcastStream()
      .where((e) => e is Map && e['type'] == 'onDraftSaved')
      .map((e) {
    final m = e as Map;
    return DraftSaved(
      url: m['url'] as String,
      title: m['title'] as String,
      durationMinutes: (m['durationMinutes'] as num).toInt(),
    );
  });
}
