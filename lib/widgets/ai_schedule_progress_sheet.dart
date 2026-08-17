import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../courses/ai_schedule_runner.dart';
import '../courses/link_course.dart';
import '../utils/time_utils.dart';
import 'app_modal_sheet.dart';

/// AI 排课对话视图：像与 AI 对话一样实时展示思考过程与输出。
/// 进度面板与排课弹窗（排课中状态）共用。
class AiScheduleConversation extends StatelessWidget {
  const AiScheduleConversation({super.key, required this.store});

  final LinkCourseStore store;

  static const _weekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  String _dateLabel(DateTime date) {
    final w = _weekdayNames[date.weekday - 1];
    return '${date.month}月${date.day}日 $w';
  }

  String _timeLabel(int minute) => formatMinutes(minute);

  List<Widget> _courseRows(BuildContext context, AiScheduleTask task) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    for (final courseId in task.courseIds) {
      final course = store.courseById(courseId);
      if (course == null) continue;
      final slots = store.slots.where((s) => s.courseId == courseId).toList()
        ..sort((a, b) {
          final da = a.epochDay ?? 0;
          final db = b.epochDay ?? 0;
          return da != db
              ? da.compareTo(db)
              : a.startMinute.compareTo(b.startMinute);
        });
      final title = course.title;
      if (slots.isEmpty) {
        rows.add(
          _row(
            title,
            trailing: Text(
              '未排上',
              style: TextStyle(fontSize: 13, color: theme.colorScheme.error),
            ),
          ),
        );
        continue;
      }
      // 多段（课程内插入休息）→ 显示为两截并用"休息"标记分隔。
      final parts = [
        for (final slot in slots)
          () {
            final date = slot.epochDay == null
                ? null
                : localDateFromEpochDay(slot.epochDay!);
            return date == null
                ? '${_timeLabel(slot.startMinute)}-${_timeLabel(slot.endMinute)}'
                : '${_dateLabel(date)} ${_timeLabel(slot.startMinute)}-${_timeLabel(slot.endMinute)}';
          }(),
      ];
      final trailingText = parts.join(slots.length > 1 ? ' ｜ 休息 ｜ ' : '');
      rows.add(
        _row(
          title,
          trailing: Text(trailingText, style: const TextStyle(fontSize: 13)),
        ),
      );
    }
    return rows;
  }

  Widget _row(String title, {required Widget trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }

  /// AI 侧气泡：流式输出的思考过程（实时累积，像 AI 在打字）。
  Widget _aiBubble(BuildContext context, AiScheduleTask task) {
    final theme = Theme.of(context);
    final thinking = task.thinking;
    final streaming = task.phase == AiSchedulePhase.requestingAi;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'AI',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                if (streaming)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // 流式输出容器：reverse 让视图始终钉在最新内容（自动滚动）。
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                reverse: true,
                child: Text(
                  thinking.isEmpty
                      ? (streaming ? '正在思考排课方案…' : '（无输出）')
                      : thinking + (streaming ? ' ▌' : ''),
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: AiScheduleRunner.instance,
      builder: (context, child) {
        final task = AiScheduleRunner.instance.task;
        if (task == null || task.phase == AiSchedulePhase.idle) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('去未排课池勾选课程开始 AI 排课吧')),
          );
        }

        final done = task.phase == AiSchedulePhase.done;
        final failed = task.phase == AiSchedulePhase.failed;
        final String statusText;
        switch (task.phase) {
          case AiSchedulePhase.requestingAi:
            statusText = 'AI 思考中，正在输出排课方案…';
            break;
          case AiSchedulePhase.placing:
            statusText = 'AI 已输出方案，正在安排课程…';
            break;
          case AiSchedulePhase.done:
            statusText =
                '排课完成：${task.placedCount} 门已安排'
                '${task.failureCount == 0 ? '' : '，${task.failureCount} 门未能排上'}';
            break;
          case AiSchedulePhase.failed:
            statusText = '排课失败';
            break;
          case AiSchedulePhase.idle:
            statusText = '';
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 状态行。
            Row(
              children: [
                if (!done && !failed)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    done ? Icons.check_circle : Icons.error_outline,
                    color: done ? Colors.green : theme.colorScheme.error,
                    size: 20,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 对话式展示：用户请求（完整提示词，文件名内联可点击）→ AI 流式输出。
            _UserPromptBubble(task: task),
            const SizedBox(height: 12),
            _aiBubble(context, task),
            const SizedBox(height: 12),
            // AI 的排课思路说明（完成后展示）。
            if (task.aiReason != null && task.aiReason!.isNotEmpty) ...[
              Text('AI 的排课思路', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(task.aiReason!, style: theme.textTheme.bodySmall),
              ),
              const SizedBox(height: 12),
            ],
            // 失败原因。
            if (failed && task.error != null) ...[
              Text('失败原因', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  task.error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text('课程仍保留在未排课池，可修改后重新排课', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
            ],
            // 课程安排明细。
            if (done || task.phase == AiSchedulePhase.placing) ...[
              Text('课程安排', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              ..._courseRows(context, task),
            ],
          ],
        );
      },
    );
  }
}

/// 排课进度面板：展示后台 AI 排课的对话过程与结果。
class AiScheduleProgressSheet extends StatelessWidget {
  const AiScheduleProgressSheet({super.key, required this.store, this.onRerun});

  final LinkCourseStore store;

  /// 完成/失败后"重新排课"回调（由调用方清空槽位并重新打开排课设置弹窗）。
  final Future<void> Function(AiScheduleTask task)? onRerun;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AiScheduleRunner.instance,
      builder: (context, child) {
        final task = AiScheduleRunner.instance.task;
        if (task == null || task.phase == AiSchedulePhase.idle) {
          return const AppSheetScaffold(
            heightFactor: 0.84,
            title: Text('AI 排课'),
            subtitle: Text('暂无排课任务'),
            actions: [],
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('去未排课池勾选课程开始 AI 排课吧')),
            ),
          );
        }
        final done = task.phase == AiSchedulePhase.done;
        final failed = task.phase == AiSchedulePhase.failed;
        final rerun = onRerun;
        return AppSheetScaffold(
          heightFactor: 0.84,
          title: const Text('AI 排课'),
          subtitle: Text(
            done || failed
                ? '开始于 ${task.startedAt.hour.toString().padLeft(2, '0')}:${task.startedAt.minute.toString().padLeft(2, '0')}'
                : '后台进行中，可关闭本面板',
          ),
          actions: [
            if (done && rerun != null)
              TextButton(
                onPressed: () => rerun(task),
                child: const Text('重新排课'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
          child: AiScheduleConversation(store: store),
        );
      },
    );
  }
}

/// 用户侧气泡：显示完整提示词（从"你是…"开始），
/// 提示词中引用的文件名（如 *.json / *.md）带下划线、点击可查看文件内容。
class _UserPromptBubble extends StatelessWidget {
  const _UserPromptBubble({required this.task});

  final AiScheduleTask task;

  Future<void> _showFile(BuildContext context, String name, String content) {
    return showAppModalSheet<void>(
      context: context,
      maxWidth: appSheetWidthMedium,
      builder: (sheetContext) => AppSheetScaffold(
        heightFactor: 0.9,
        title: Text(name),
        subtitle: const Text('随排课请求一起发送给 AI 的技能文件'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: const Text('关闭'),
          ),
        ],
        child: SingleChildScrollView(
          child: SelectableText(
            content,
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
        ),
      ),
    );
  }

  /// 把提示词文本拆成 spans：文件名（*.json / *.md）渲染为带下划线的链接。
  List<InlineSpan> _buildSpans(
    BuildContext context,
    String text,
    Map<String, String> files,
  ) {
    final theme = Theme.of(context);
    final linkColor = theme.colorScheme.primary;
    final pattern = RegExp(r'[\w-]+\.(?:json|md)');
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, m.start)));
      }
      final name = m.group(0)!;
      spans.add(
        TextSpan(
          text: name,
          style: TextStyle(
            color: linkColor,
            decoration: TextDecoration.underline,
            decorationColor: linkColor.withValues(alpha: 0.7),
            fontWeight: FontWeight.w600,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              final content = files[name];
              if (content != null) _showFile(context, name, content);
            },
        ),
      );
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pkg = task.skillPackage;
    final messages = task.sentMessages;
    // 完整提示词优先取实际发送的 system 消息；否则取技能包系统提示词。
    String? prompt;
    Map<String, String> files = {};
    for (final m in messages) {
      if (m['role'] == 'system') {
        prompt = m['content'];
        break;
      }
    }
    if (prompt == null && pkg != null) {
      prompt = pkg.systemPrompt;
    }
    if (pkg != null) {
      files = {
        ...pkg.schemeFiles,
        'system_prompt.md': pkg.systemPrompt,
        'user_prompt.md': pkg.userTemplate,
      };
    }
    final text = (prompt ?? '').trim();
    // 去掉 Markdown 标题行（# 开头）。
    final cleaned = text.replaceFirst(RegExp(r'^#.*\n+'), '');
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.9,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '发给 AI 的完整提示词',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer.withValues(
                  alpha: 0.7,
                ),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            if (cleaned.isEmpty)
              Text(
                '请使用软件技能为这 ${task.courseIds.length} 节课进行排序,注意用户的要求设置。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  height: 1.45,
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: SingleChildScrollView(
                  child: Text.rich(
                    TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        height: 1.45,
                      ),
                      children: _buildSpans(context, cleaned, files),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
