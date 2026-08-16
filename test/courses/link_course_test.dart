import 'package:flutter_test/flutter_test.dart';
import 'package:linkstudy/courses/link_course.dart';

void main() {
  setUp(() {
    // FakeAsync 环境下真实文件 I/O 会挂起，跳过持久化。
    LinkCourseStore.instance.debugSkipPersist = true;
  });

  final availability = availabilityFromDayWindow(
    startMinute: 8 * 60,
    lunchStartMinute: 12 * 60,
    lunchEndMinute: 13 * 60,
    endMinute: 22 * 60,
  );

  group('LinkCourseStore 入池与排课', () {
    test('addCourse 后进入未排课池，不自动排课', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      final course = await store.addCourse(
        url: 'https://example.com/1',
        title: '考研英语',
        durationMinutes: 40,
      );
      expect(store.pendingCount, 1);
      expect(store.slots, isEmpty);
      expect(store.courseById(course.id), isNotNull);
    });

    test('scheduleWithOrder 按 AI 顺序落位并清空池子', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      final a = await store.addCourse(
        url: 'https://example.com/a',
        title: '课程A',
        durationMinutes: 40,
      );
      final b = await store.addCourse(
        url: 'https://example.com/b',
        title: '课程B',
        durationMinutes: 40,
      );
      final result = await store.scheduleWithOrder(
        courseIds: [a.id, b.id],
        ordered: [
          (courseId: a.id, restAfterMinutes: 20),
          (courseId: b.id, restAfterMinutes: 0),
        ],
        days: 7,
        availabilityByWeekday: availability,
        // 从固定日期(明天)开始,避免真实时间影响(现在时间不同会导致今天窗口不足)。
        startFromNow: false,
        anchorDate: DateTime(2026, 1, 6),
      );
      expect(result.failures, isEmpty);
      expect(result.placements, hasLength(2));
      expect(store.slots, hasLength(2));
      expect(store.pendingCount, 0);
      final aSlot = store.slots.singleWhere((s) => s.courseId == a.id);
      final bSlot = store.slots.singleWhere((s) => s.courseId == b.id);
      expect(aSlot.epochDay, isNotNull);
      // a 之后有 20 分钟休息 → b 不紧贴 a（可能顺延到下一时段，故为"至少"）。
      expect(bSlot.startMinute, greaterThanOrEqualTo(aSlot.endMinute + 20));
      // 排序稳定：a 的排课位置不晚于 b。
      final aKey = (aSlot.epochDay ?? 0) * 10000 + aSlot.startMinute;
      final bKey = (bSlot.epochDay ?? 0) * 10000 + bSlot.startMinute;
      expect(aKey, lessThanOrEqualTo(bKey));
    });

    test('scheduleWithOrder 携带课程颜色到槽位', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      final a = await store.addCourse(
        url: 'https://example.com/color-a',
        title: '颜色课程',
        durationMinutes: 40,
      );
      await store.scheduleWithOrder(
        courseIds: [a.id],
        ordered: [(courseId: a.id, restAfterMinutes: 0)],
        days: 7,
        availabilityByWeekday: availability,
        startFromNow: false,
        courseColors: {a.id: 0xFF4D6BFE},
      );
      expect(store.slots.single.colorValue, 0xFF4D6BFE);
    });

    test('AI 具体时间落位：采用 AI 时间并校验时间窗/时长/不重叠', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      final a = await store.addCourse(
        url: 'https://example.com/ai-time-a',
        title: '数据结构',
        durationMinutes: 100,
      );
      final b = await store.addCourse(
        url: 'https://example.com/ai-time-b',
        title: 'Java',
        durationMinutes: 90,
      );
      // AI 输出具体时间：a 在第二天 9:00-10:40，b 在第二天 14:00-15:30
      // （避开午休 12:00-13:00，且不早于 9:00、不挤在上午）。
      final result = await store.scheduleWithOrder(
        courseIds: [a.id, b.id],
        ordered: [
          (courseId: a.id, restAfterMinutes: 20),
          (courseId: b.id, restAfterMinutes: 0),
        ],
        days: 2,
        availabilityByWeekday: availability,
        startFromNow: false,
        aiPlacements: [
          AiPlacement(
            courseId: a.id,
            dayOffset: 1,
            startMinute: 9 * 60,
            endMinute: 9 * 60 + 100,
          ),
          AiPlacement(
            courseId: b.id,
            dayOffset: 1,
            startMinute: 14 * 60,
            endMinute: 14 * 60 + 90,
          ),
        ],
      );
      expect(result.failures, isEmpty);
      expect(result.placements, hasLength(2));
      final aSlot = store.slots.singleWhere((s) => s.courseId == a.id);
      final bSlot = store.slots.singleWhere((s) => s.courseId == b.id);
      expect(aSlot.startMinute, 9 * 60);
      expect(aSlot.endMinute, 9 * 60 + 100);
      expect(bSlot.startMinute, 14 * 60);
      // 都在第二天。
      expect(aSlot.epochDay, bSlot.epochDay);
    });

    test('课程内休息：同课拆多段，段间空隙即休息', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      // 100 分钟课：AI 拆成 50 + 休息10 + 50（09:00-09:50、10:00-10:50）。
      final a = await store.addCourse(
        url: 'https://example.com/break',
        title: '数据结构',
        durationMinutes: 100,
      );
      final result = await store.scheduleWithOrder(
        courseIds: [a.id],
        ordered: [(courseId: a.id, restAfterMinutes: 0)],
        days: 7,
        availabilityByWeekday: availability,
        startFromNow: false,
        aiPlacements: [
          AiPlacement(
            courseId: a.id,
            dayOffset: 1,
            startMinute: 9 * 60,
            endMinute: 9 * 60 + 50,
          ),
          AiPlacement(
            courseId: a.id,
            dayOffset: 1,
            startMinute: 10 * 60,
            endMinute: 10 * 60 + 50,
          ),
        ],
      );
      expect(result.failures, isEmpty);
      // 同课两段 → 两个槽位。
      final slots =
          store.slots.where((s) => s.courseId == a.id).toList()
            ..sort((x, y) => x.startMinute.compareTo(y.startMinute));
      expect(slots, hasLength(2));
      expect(slots[0].startMinute, 9 * 60);
      expect(slots[0].endMinute, 9 * 60 + 50);
      // 段间空隙 09:50-10:00 即休息。
      expect(slots[1].startMinute - slots[0].endMinute, 10);
      expect(slots[1].endMinute, 10 * 60 + 50);
    });

    test('AI 具体时间非法时回退本地贪心落位', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      final a = await store.addCourse(
        url: 'https://example.com/ai-bad',
        title: '非法时间课',
        durationMinutes: 40,
      );
      // AI 时间与课程时长不符 → 应被拒绝，回退本地落位。
      final result = await store.scheduleWithOrder(
        courseIds: [a.id],
        ordered: [(courseId: a.id, restAfterMinutes: 0)],
        days: 7,
        availabilityByWeekday: availability,
        aiPlacements: [
          const AiPlacement(
            courseId: 'a',
            dayOffset: 0,
            startMinute: 9 * 60,
            endMinute: 9 * 60 + 200, // 200 分钟 ≠ 课程 40 分钟
          ),
        ],
      );
      expect(result.failures, isEmpty);
      final slot = store.slots.single;
      // 本地回退：时长恢复为课程时长 40 分钟。
      expect(slot.endMinute - slot.startMinute, 40);
    });

    test('颜色兜底：AI 未给颜色时每门课颜色不同', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      final a = await store.addCourse(
        url: 'https://example.com/color-a',
        title: '课程A',
        durationMinutes: 40,
      );
      final b = await store.addCourse(
        url: 'https://example.com/color-b',
        title: '课程B',
        durationMinutes: 40,
      );
      await store.scheduleWithOrder(
        courseIds: [a.id, b.id],
        ordered: [
          (courseId: a.id, restAfterMinutes: 0),
          (courseId: b.id, restAfterMinutes: 0),
        ],
        days: 7,
        availabilityByWeekday: availability,
      );
      final aSlot = store.slots.singleWhere((s) => s.courseId == a.id);
      final bSlot = store.slots.singleWhere((s) => s.courseId == b.id);
      expect(aSlot.colorValue, isNotNull);
      expect(bSlot.colorValue, isNotNull);
      expect(aSlot.colorValue, isNot(bSlot.colorValue));
    });

    test('AI 失败回退：ordered 为空时按默认贪心落位', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      final course = await store.addCourse(
        url: 'https://example.com/fallback',
        title: '回退课程',
        durationMinutes: 60,
      );
      final result = await store.scheduleWithOrder(
        courseIds: [course.id],
        ordered: const [],
        days: 7,
        availabilityByWeekday: availability,
      );
      expect(result.failures, isEmpty);
      expect(store.slots, hasLength(1));
      expect(store.pendingCount, 0);
    });

    test('schedulePending 贪心兜底仍可用', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      await store.addCourse(
        url: 'https://example.com/greedy',
        title: '贪心课程',
        durationMinutes: 40,
      );
      final result = await store.schedulePending();
      expect(result.failures, isEmpty);
      expect(store.slots, hasLength(1));
    });

    test('removeSlotForCourse 移除槽位（网格删除联动，课程回池）', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      final course = await store.addCourse(
        url: 'https://example.com/slot-remove',
        title: '联动课程',
        durationMinutes: 40,
      );
      await store.schedulePending();
      expect(store.slots, hasLength(1));
      await store.removeSlotForCourse(course.id);
      expect(store.slots, isEmpty);
      expect(store.pendingCount, 1);
    });

    test('删除课程同时移除其槽位', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      final course = await store.addCourse(
        url: 'https://example.com/del',
        title: '待删课程',
        durationMinutes: 40,
      );
      await store.schedulePending();
      expect(store.slots, hasLength(1));
      await store.deleteCourse(course.id);
      expect(store.courses, isEmpty);
      expect(store.slots, isEmpty);
    });
  });
}
