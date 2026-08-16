import 'package:flutter_test/flutter_test.dart';
import 'package:linkstudy/courses/course_ingest_service.dart';
import 'package:linkstudy/courses/link_course.dart';

void main() {
  group('CourseIngestService.ingest', () {
    test('合法草稿成功入库', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      final service = CourseIngestService(store: store);
      final result = await service.ingest(
        const CourseDraft(
          url: 'https://pan.quark.cn/s/abc123',
          title: '考研英语',
          durationMinutes: 40,
        ),
      );
      expect(result.success, isTrue);
      expect(result.course!.url, 'https://pan.quark.cn/s/abc123');
      expect(result.course!.title, '考研英语');
      expect(result.course!.durationMinutes, 40);
      expect(store.courses, hasLength(1));
    });

    test('从混合文本中提取 URL 并入库', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      final service = CourseIngestService(store: store);
      final result = await service.ingest(
        const CourseDraft(
          url: '看这个网课 https://www.bilibili.com/video/BV1xx 强烈推荐',
          title: '',
          durationMinutes: 30,
        ),
      );
      expect(result.success, isTrue);
      expect(result.course!.url, 'https://www.bilibili.com/video/BV1xx');
    });

    test('标题为空时从 URL 自动提取', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      final service = CourseIngestService(store: store);
      final result = await service.ingest(
        const CourseDraft(
          url: 'https://example.com/courses/linear-algebra',
          title: '',
          durationMinutes: 60,
        ),
      );
      expect(result.success, isTrue);
      expect(result.course!.title, 'linear-algebra');
    });

    test('非法链接被拒绝', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      final service = CourseIngestService(store: store);
      final result = await service.ingest(
        const CourseDraft(url: 'not-a-url', title: 'x', durationMinutes: 40),
      );
      expect(result.success, isFalse);
      expect(result.error, contains('链接无效'));
      expect(store.courses, isEmpty);
    });

    test('时长越界被拒绝', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      final service = CourseIngestService(store: store);
      final result = await service.ingest(
        const CourseDraft(
          url: 'https://example.com',
          title: 'x',
          durationMinutes: 700,
        ),
      );
      expect(result.success, isFalse);
      expect(result.error, contains('时长'));
    });

    test('URL 选填：标题+时长完整时无链接也能入库', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      final service = CourseIngestService(store: store);
      final result = await service.ingest(
        const CourseDraft(url: '', title: '手打笔记课程', durationMinutes: 45),
      );
      expect(result.success, isTrue);
      expect(result.course!.url, isEmpty);
      expect(result.course!.title, '手打笔记课程');
      expect(store.courses, hasLength(1));
    });

    test('标题为空且无法提取时被拒绝', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      final service = CourseIngestService(store: store);
      final result = await service.ingest(
        const CourseDraft(url: 'https://', title: '', durationMinutes: 40),
      );
      expect(result.success, isFalse);
    });
  });

  group('CourseIngestService.extractUrls', () {
    test('提取文本中的多个链接', () {
      final service = CourseIngestService(store: LinkCourseStore.instance);
      final urls = service.extractUrls('a https://x.com/1 b https://y.com/2 c');
      expect(urls, ['https://x.com/1', 'https://y.com/2']);
    });
  });
}
