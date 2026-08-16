import 'dart:async';

import 'package:flutter/foundation.dart';

import '../platform/overlay_client.dart';
import '../services/notification_service.dart';
import 'ai_scheduler.dart';
import 'ai_skill_package.dart';
import 'link_course.dart';
import 'scheduler_engine.dart';

/// 后台排课任务阶段。
enum AiSchedulePhase {
  idle,
  requestingAi, // 请求 AI 中（思考过程第一阶段）
  placing, // AI 已返回，本地落位中
  done, // 完成
  failed, // 失败（保留在未排课池）
}

/// 一次后台排课任务的状态与结果。
class AiScheduleTask {
  AiScheduleTask({
    required this.id,
    required this.courseIds,
    required this.prefs,
    required this.availability,
    required this.windowDescription,
    required this.localeCode,
    this.occupiedEvents = '',
  }) : startedAt = DateTime.now();

  final String id;
  final List<String> courseIds;
  final AiSchedulePrefs prefs;
  final List<List<AvailabilitySlot>> availability;
  final String windowDescription;
  final String localeCode;

  /// 排课窗口内用户已排日程的文本描述（防止课程与日程时间冲突）。
  final String occupiedEvents;

  final DateTime startedAt;

  AiSchedulePhase phase = AiSchedulePhase.requestingAi;
  String? aiReason; // AI 给出的排课思路（思考过程）
  List<OrderedCourse>? ordered;
  int placedCount = 0;
  int failureCount = 0;
  String? error;
  DateTime? finishedAt;

  /// 流式思考过程：AI 生成的原始输出（实时累积，进度面板对话式展示）。
  String thinking = '';

  /// 实际发送给 AI 的完整消息（面板展示"发给 AI 的提示词"用）。
  List<Map<String, String>> sentMessages = const [];

  /// 本次排课使用的技能文件包（面板展示提示词内联文件名链接用）。
  AiSkillPackage? skillPackage;

  /// 结果是否已被用户查看过（控制排课按钮是否优先打开进度面板）。
  bool viewed = false;
}

/// 后台静默排课：启动后任务在后台执行，弹窗/页面可随时关闭；
/// 完成后发本地通知，用户可重新打开查看进度与结果（思考过程）。
class AiScheduleRunner extends ChangeNotifier {
  AiScheduleRunner._();

  static final AiScheduleRunner instance = AiScheduleRunner._();

  AiScheduleTask? _task;

  AiScheduleTask? get task => _task;

  bool get isRunning {
    final t = _task;
    return t != null &&
        (t.phase == AiSchedulePhase.requestingAi ||
            t.phase == AiSchedulePhase.placing);
  }

  /// 是否有已完成但未被查看的任务（排课按钮优先打开进度面板展示结果）。
  bool get hasUnviewedResult {
    final t = _task;
    return t != null &&
        !t.viewed &&
        (t.phase == AiSchedulePhase.done || t.phase == AiSchedulePhase.failed);
  }

  /// 标记最近任务结果已查看。
  void markViewed() {
    final t = _task;
    if (t == null || t.viewed) return;
    t.viewed = true;
    notifyListeners();
  }

  /// 启动后台排课（快照所有输入，弹窗关闭后任务仍可执行）。
  Future<void> start({
    required List<String> courseIds,
    required AiSchedulePrefs prefs,
    required List<List<AvailabilitySlot>> availability,
    required String windowDescription,
    required String localeCode,
    String occupiedEvents = '',
    AiScheduler? scheduler,
    LinkCourseStore? store,
    AiScheduleSettings? settings,
    NotificationService? notifications,
    Future<AiSkillPackage?> Function()? skillLoader,
    Duration timeout = const Duration(seconds: 600),
  }) async {
    if (isRunning) return;
    final runnerStore = store ?? LinkCourseStore.instance;
    final runnerSettings = settings ?? AiScheduleSettings();
    final notifier = notifications ?? NotificationService.instance;

    _task = AiScheduleTask(
      id: 'task_${DateTime.now().microsecondsSinceEpoch}',
      courseIds: List.unmodifiable(courseIds),
      prefs: prefs,
      availability: availability,
      windowDescription: windowDescription,
      localeCode: localeCode,
      occupiedEvents: occupiedEvents,
    );
    notifyListeners();

    // Android 13+ 通知权限。
    try {
      await OverlayClient().requestNotificationPermission();
    } catch (_) {}

    // 记住本次排课设置（下次预填）。
    try {
      await runnerSettings.saveSetupPrefs(prefs);
    } catch (_) {}

    try {
      final task = _task!;
      // 阶段 1：请求 AI（超时放宽到后台可承受范围）。
      final config = await runnerSettings.loadConfig(
        windowDescription: windowDescription,
      );
      final requestConfig = AiScheduleConfig(
        provider: config.provider,
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
        model: config.model,
        windowDescription: config.windowDescription,
        timeout: timeout,
      );
      final courses = task.courseIds
          .map(runnerStore.courseById)
          .whereType<LinkCourse>()
          .toList();
      task.phase = AiSchedulePhase.requestingAi;
      notifyListeners();

      // 加载排课技能文件包（md 提示词 + 算法 JSON）；加载失败时降级内置 prompt。
      final skillPackage =
          await (skillLoader ?? const AiSkillPackageLoader().load)();
      task.skillPackage = skillPackage;
      notifyListeners();

      final outcome = await (scheduler ?? AiScheduler()).schedule(
        courses: courses,
        prefs: prefs,
        config: requestConfig,
        localeCode: localeCode,
        skillPackage: skillPackage,
        occupiedEvents: task.occupiedEvents,
        onMessages: (messages) {
          task.sentMessages = messages;
          notifyListeners();
        },
        onToken: (delta) {
          task.thinking += delta;
          notifyListeners();
        },
        onUsage: (prompt, completion) {
          // 记录 token 用量（按 provider+model 累计）。
          unawaited(
            AiUsageStats.instance.record(
              provider: config.provider,
              model: config.model,
              promptTokens: prompt,
              completionTokens: completion,
            ),
          );
        },
      );

      switch (outcome) {
        case AiScheduleOutcomeSuccess(:final value):
          task.ordered = value.ordered
              .where((o) => task.courseIds.contains(o.courseId))
              .toList();
          task.aiReason = value.reason;
          // 阶段 2：本地落位。
          task.phase = AiSchedulePhase.placing;
          notifyListeners();
          final result = await runnerStore.scheduleWithOrder(
            courseIds: task.courseIds,
            ordered: task.ordered!,
            days: prefs.days,
            availabilityByWeekday: task.availability,
            startFromNow: prefs.startMode == ScheduleStartMode.now,
            anchorDate: prefs.startDate,
            courseColors: value.colors,
            aiPlacements: value.placements,
          );
          task.placedCount = result.placements.length;
          task.failureCount = result.failures.length;
          task.phase = AiSchedulePhase.done;
          notifyListeners();
          final failNote = task.failureCount == 0
              ? ''
              : '，${task.failureCount} 门未能排上';
          await notifier.showScheduleResult(
            success: true,
            message: '${task.placedCount} 门已安排$failNote，点击查看排课详情',
          );
        case AiScheduleOutcomeError(:final error):
          task.error = error.message;
          task.phase = AiSchedulePhase.failed;
          notifyListeners();
          await notifier.showScheduleResult(
            success: false,
            message: error.message,
          );
      }
    } catch (e) {
      final task = _task!;
      task.error = '$e';
      task.phase = AiSchedulePhase.failed;
      notifyListeners();
      try {
        await notifier.showScheduleResult(success: false, message: '$e');
      } catch (_) {}
    } finally {
      _task?.finishedAt = DateTime.now();
      notifyListeners();
    }
  }

  /// 仅测试用：清空任务状态。
  @visibleForTesting
  void debugReset() {
    _task = null;
    notifyListeners();
  }
}
