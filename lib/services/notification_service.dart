import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 本地通知服务：后台 AI 排课完成/失败时提醒用户。
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// 仅测试用：跳过真实通知发送（避免平台通道在测试环境抛异常）。
  @visibleForTesting
  bool debugSkipSend = false;

  static const _channelId = 'ai_schedule';
  static const _channelName = 'AI 排课';

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  /// 排课完成/失败通知（success=false 时展示失败原因）。
  Future<void> showScheduleResult({
    required bool success,
    required String message,
  }) async {
    if (debugSkipSend) return;
    await ensureInitialized();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'AI 排课完成与失败提醒',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _plugin.show(
      id: success ? 1001 : 1002,
      title: success ? 'AI 排课完成' : 'AI 排课失败',
      body: message,
      notificationDetails: details,
    );
  }
}
