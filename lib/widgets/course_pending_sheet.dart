import 'package:flutter/material.dart';

import '../courses/course_ingest_service.dart';
import '../courses/link_course.dart';
import 'app_modal_sheet.dart';

/// 未排课池弹窗：展示待安排课程，支持勾选/全选/删除，返回勾选的课程 id 列表。
/// 卡片布局：最左圆形勾选框（垂直居中）｜上行：课程名（左）+ 时长（右）；下行：链接地址。
class CoursePendingSheet extends StatefulWidget {
  const CoursePendingSheet({super.key, required this.store});

  final LinkCourseStore store;

  @override
  State<CoursePendingSheet> createState() => _CoursePendingSheetState();
}

class _CoursePendingSheetState extends State<CoursePendingSheet> {
  final Set<String> _selected = {};
  bool _deleting = false;
  bool _adding = false;

  List<LinkCourse> get _pending {
    final store = widget.store;
    return store.courses
        .where((c) => !store.slots.any((s) => s.courseId == c.id))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    if (count == 0 || _deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除课程'),
        content: Text('确定删除已勾选的 $count 门课程吗？删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      for (final id in _selected.toList()) {
        await widget.store.deleteCourse(id);
      }
      if (mounted) {
        setState(() {
          _selected.clear();
          _deleting = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  /// 手动添加课程（不依赖悬浮窗）：半弹窗表单录入 URL/名称/时长/优先级/截止日期，入库后进入未排课池。
  Future<void> _addCourse() async {
    if (_adding) return;
    final urlController = TextEditingController();
    final titleController = TextEditingController();
    final durationController = TextEditingController(text: '40');
    var priority = CoursePriority.medium;
    DateTime? deadline;

    String? errorText;

    final saved = await showAppModalSheet<bool>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> pickDeadline() async {
              final picked = await showDatePicker(
                context: context,
                initialDate:
                    deadline ?? DateTime.now().add(const Duration(days: 1)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                setSheetState(() => deadline = picked);
              }
            }

            void save() {
              final duration = int.tryParse(durationController.text.trim());
              if (duration == null || duration < 1 || duration > 600) {
                setSheetState(() => errorText = '时长需为 1-600 的整数（分钟）');
                return;
              }
              if (titleController.text.trim().isEmpty) {
                setSheetState(() => errorText = '请填写课程名称');
                return;
              }
              Navigator.of(sheetContext).pop(true);
            }

            return AppSheetScaffold(
              title: const Text('添加课程'),
              subtitle: const Text('填写课程信息，保存后进入未排课池'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(onPressed: save, child: const Text('保存')),
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: urlController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: '链接 URL（选填）',
                      hintText: 'https://…（可选）',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: '课程名称（必填）',
                      hintText: '例如：数据结构与算法',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: durationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '时长（分钟，必填，1-600）',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<CoursePriority>(
                    initialValue: priority,
                    decoration: const InputDecoration(
                      labelText: '优先级',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: CoursePriority.high,
                        child: Text('高'),
                      ),
                      DropdownMenuItem(
                        value: CoursePriority.medium,
                        child: Text('中'),
                      ),
                      DropdownMenuItem(
                        value: CoursePriority.low,
                        child: Text('低'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setSheetState(() => priority = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: pickDeadline,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      deadline == null
                          ? '截止日期：无（可选）'
                          : '截止日期：${deadline!.year}-${deadline!.month.toString().padLeft(2, '0')}-${deadline!.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );

    if (saved != true || !mounted) return;
    final duration = int.parse(durationController.text.trim());

    setState(() => _adding = true);
    try {
      final service = CourseIngestService(store: widget.store);
      final result = await service.ingest(
        CourseDraft(
          url: urlController.text,
          title: titleController.text,
          durationMinutes: duration,
          deadlineDay: deadline == null ? null : epochDayOf(deadline!),
          priority: priority,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result.success
                  ? '已添加《${result.course!.title}》，可在池中勾选后排课'
                  : '添加失败：${result.error}',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, child) {
        final pending = _pending;
        final allSelected =
            pending.isNotEmpty &&
            pending.every((c) => _selected.contains(c.id));
        return AppSheetScaffold(
          title: Text('未排课课程（${pending.length}）'),
          subtitle: const Text('勾选要安排学习的课程，可添加、全选或删除'),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: _adding ? null : _addCourse,
                icon: const Icon(Icons.add),
                label: const Text('添加'),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: pending.isEmpty
                    ? null
                    : () => setState(() {
                        if (allSelected) {
                          _selected.clear();
                        } else {
                          _selected
                            ..clear()
                            ..addAll(pending.map((c) => c.id));
                        }
                      }),
                icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
                label: Text(allSelected ? '取消全选' : '全选'),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '删除勾选课程',
              onPressed: _selected.isEmpty || _deleting
                  ? null
                  : _deleteSelected,
              icon: const Icon(Icons.delete_outline),
            ),
            FilledButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_selected.toList()),
              child: const Text('下一步'),
            ),
          ],
          child: pending.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text('暂无未排课课程，先去悬浮窗采集一些吧')),
                )
              : Column(
                  children: [
                    for (final course in pending)
                      _PendingCourseCard(
                        course: course,
                        selected: _selected.contains(course.id),
                        onToggle: () => setState(() {
                          if (!_selected.add(course.id)) {
                            _selected.remove(course.id);
                          }
                        }),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _PendingCourseCard extends StatelessWidget {
  const _PendingCourseCard({
    required this.course,
    required this.selected,
    required this.onToggle,
  });

  final LinkCourse course;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? colorScheme.primaryContainer.withValues(alpha: 0.35)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _RoundCheckbox(value: selected, onChanged: onToggle),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              course.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${course.durationMinutes} 分钟',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        course.url.isEmpty ? '无链接' : course.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 圆形勾选框（选中：主题色填充 + 白色对勾）。
class _RoundCheckbox extends StatelessWidget {
  const _RoundCheckbox({required this.value, required this.onChanged});

  final bool value;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onChanged,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: value ? colorScheme.primary : Colors.transparent,
          border: Border.all(
            color: value ? colorScheme.primary : colorScheme.outline,
            width: 2,
          ),
        ),
        child: value
            ? Icon(Icons.check, size: 16, color: colorScheme.onPrimary)
            : null,
      ),
    );
  }
}
