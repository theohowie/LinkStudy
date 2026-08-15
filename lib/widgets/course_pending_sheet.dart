import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, child) {
        final pending = _pending;
        final allSelected =
            pending.isNotEmpty && pending.every((c) => _selected.contains(c.id));
        return AppSheetScaffold(
          title: Text('未排课课程（${pending.length}）'),
          subtitle: const Text('勾选要安排学习的课程，可全选或删除'),
          leading: TextButton.icon(
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
          actions: [
            IconButton(
              tooltip: '删除勾选课程',
              onPressed: _selected.isEmpty || _deleting ? null : _deleteSelected,
              icon: const Icon(Icons.delete_outline),
            ),
            FilledButton(
              onPressed: _selected.isEmpty ? null : () => Navigator.of(context).pop(_selected.toList()),
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
