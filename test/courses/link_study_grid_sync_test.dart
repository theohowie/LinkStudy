import 'package:flutter_test/flutter_test.dart';
import 'package:linkstudy/courses/link_course.dart';
import 'package:linkstudy/courses/link_study_grid_sync.dart';
import 'package:linkstudy/data/timetable_storage.dart';
import 'package:linkstudy/models/app_data.dart';
import 'package:linkstudy/models/general_models.dart';
import 'package:linkstudy/providers/timetable_provider.dart';

class _MemoryTimetableStorage implements TimetableStorage {
  _MemoryTimetableStorage(this.data);

  AppData? data;

  @override
  Future<StorageLoadResult> load() async =>
      StorageLoadResult(data: data, recoveryStatus: RecoveryStatus.none);

  @override
  Future<void> save(AppData data) async {
    this.data = data;
  }

  @override
  Future<String?> filePath() async => 'memory://grid-sync-test';
}

LinkCourse _course(String id, String title) => LinkCourse(
      id: id,
      url: 'https://example.com/$id',
      title: title,
      durationMinutes: 40,
      createdAt: DateTime(2026, 1, 5),
    );

void main() {
  group('gridEventAnchor', () {
    test('优先使用排课日期（epochDay）', () {
      final slot = ScheduleSlot(
        courseId: 'c1',
        epochDay: epochDayOf(DateTime(2026, 1, 7)),
        weekday: 3,
        startMinute: 19 * 60,
        endMinute: 19 * 60 + 40,
      );
      // 即使 today 是其他日期，也锚定到排课日期。
      expect(
        gridEventAnchor(slot, DateTime(2026, 1, 5)),
        DateTime(2026, 1, 7),
      );
    });

    test('旧数据无日期时回退到本周该 weekday', () {
      final slot = ScheduleSlot(
        courseId: 'c1',
        weekday: 3,
        startMinute: 19 * 60,
        endMinute: 19 * 60 + 40,
      );
      // 2026-01-05 是周一 → 本周三为 2026-01-07。
      expect(
        gridEventAnchor(slot, DateTime(2026, 1, 5)),
        DateTime(2026, 1, 7),
      );
    });
  });

  group('buildGridEvent', () {
    test('悬浮窗课程默认不重复，锚定到排课日期', () {
      final slot = ScheduleSlot(
        courseId: 'c1',
        epochDay: epochDayOf(DateTime(2026, 1, 7)),
        weekday: 3,
        startMinute: 19 * 60,
        endMinute: 19 * 60 + 40,
      );
      final event = buildGridEvent(
        _course('c1', '考研英语'),
        slot,
        calendarId: 'cal1',
        today: DateTime(2026, 1, 5),
      );
      expect(event.recurrence, GeneralEventRecurrence.none);
      expect(event.id, 'ls_c1');
      expect(event.startDateTimeIso, startsWith('2026-01-07T19:00'));
      expect(event.endDateTimeIso, startsWith('2026-01-07T19:40'));
    });
  });

  group('LinkStudyGridSync.sync', () {
    test('同步后课程为单次事件且日期与槽位一致', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      final provider = TimetableProvider(
        storage: _MemoryTimetableStorage(buildInitialAppData()),
      );
      await provider.load();
      final sync = LinkStudyGridSync(provider: provider, store: store);
      await sync.sync(); // 无课程：仅建日历，不报错。

      final course = await store.addCourse(
        url: 'https://example.com/overlay-1',
        title: '悬浮窗网课',
        durationMinutes: 40,
      );
      final slot = store.slots.singleWhere((s) => s.courseId == course.id);
      await sync.sync();

      final schedule = provider.generalSchedules
          .singleWhere((s) => s.name == LinkStudyGridSync.scheduleName);
      final event =
          schedule.events.singleWhere((e) => e.id == 'ls_${course.id}');
      // 不重复，且锚定到排课的具体日期。
      expect(event.recurrence, GeneralEventRecurrence.none);
      final expectedDate = localDateFromEpochDay(slot.epochDay!);
      expect(
        event.startDateTimeIso,
        startsWith(expectedDate.toIso8601String().substring(0, 10)),
      );
      expect(
        DateTime.parse(event.startDateTimeIso).hour,
        slot.startMinute ~/ 60,
      );
    });
  });
}
