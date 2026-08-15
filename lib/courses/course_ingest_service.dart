import 'link_course.dart';

/// 采集草稿：悬浮窗/外部传入的课程信息。
class CourseDraft {
  final String url;
  final String title;
  final int durationMinutes;
  final int? deadlineDay; // 可选：截止日期（epochDay）
  final CoursePriority priority;

  const CourseDraft({
    required this.url,
    required this.title,
    required this.durationMinutes,
    this.deadlineDay,
    this.priority = CoursePriority.medium,
  });
}

/// 入库结果。
class IngestResult {
  final bool success;
  final String? error; // 失败原因（success=false 时有值）
  final LinkCourse? course;

  const IngestResult.success(LinkCourse this.course)
      : success = true,
        error = null;

  const IngestResult.failure(String this.error)
      : success = false,
        course = null;
}

/// 课程入库接口：接收悬浮窗采集的课程草稿，解析校验后写入本地课程表存储。
///
/// 这是悬浮窗（采集端）与课程表存储之间的唯一入口：
/// - 解析：从 URL/文本提取合法链接，缺失标题时自动补全；
/// - 校验：URL 合法、标题非空、时长 1-600；
/// - 转发：调用 [LinkCourseStore.addCourse] 落库。
class CourseIngestService {
  CourseIngestService({LinkCourseStore? store})
      : _store = store ?? LinkCourseStore.instance;

  final LinkCourseStore _store;

  static const _urlPattern = "https?://[^\\s<>\"')\\]}，。；！？]+";

  /// 解析并入库一条课程草稿。
  Future<IngestResult> ingest(CourseDraft draft) async {
    // 1. URL 解析：必须含合法 http(s) 链接。
    final urls = extractUrls(draft.url);
    final url = urls.isNotEmpty ? urls.first : draft.url.trim();
    if (!_isHttpUrl(url)) {
      return IngestResult.failure('链接无效：请输入合法的 http(s) 链接');
    }

    // 2. 标题解析：为空时从 URL 自动提取提示。
    var title = draft.title.trim();
    if (title.isEmpty) {
      title = titleHintFromUrl(url);
    }
    if (title.isEmpty) {
      return IngestResult.failure('课程名称不能为空');
    }

    // 3. 时长校验。
    if (draft.durationMinutes < 1 || draft.durationMinutes > 600) {
      return IngestResult.failure('时长需为 1-600 的整数（分钟）');
    }

    // 4. 转发入库。
    final course = await _store.addCourse(
      url: url,
      title: title,
      durationMinutes: draft.durationMinutes,
      deadlineDay: draft.deadlineDay,
      priority: draft.priority,
    );
    return IngestResult.success(course);
  }

  /// 从一段文本中提取全部 URL。
  List<String> extractUrls(String? text) {
    if (text == null || text.trim().isEmpty) return const [];
    final reg = RegExp(_urlPattern);
    final out = <String>{};
    for (final m in reg.allMatches(text)) {
      out.add(m.group(0)!.replaceFirst(RegExp(r'[.,;:!?]+$'), ''));
    }
    return out.toList();
  }

  /// 从 URL 提取标题提示（路径最后一段或 host）。
  String titleHintFromUrl(String url) {
    try {
      final uri = Uri.parse(url.trim());
      final segments =
          uri.pathSegments.where((s) => s.isNotEmpty && s.length > 3);
      final last = segments.isEmpty ? null : segments.last;
      return last ?? uri.host;
    } catch (_) {
      return '';
    }
  }

  bool _isHttpUrl(String url) {
    final trimmed = url.trim().toLowerCase();
    return trimmed.startsWith('http://') || trimmed.startsWith('https://');
  }
}
