import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:linkstudy/models/general_event.dart';
import 'package:linkstudy/models/general_event_occurrence.dart';
import 'package:linkstudy/models/general_schedule.dart';
import 'package:linkstudy/widgets/share_schedule_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  GeneralSchedule calendar({required String name}) => GeneralSchedule(
        id: 'cal-$name',
        name: name,
        events: const [],
      );

  GeneralEvent event(String id, String title, String start, String end) =>
      GeneralEvent(
        id: id,
        title: title,
        startDateTimeIso: start,
        endDateTimeIso: end,
      );

  GeneralEventOccurrence occurrence(
    DateTime start,
    DateTime end, {
    String title = '高数基础',
  }) =>
      GeneralEventOccurrence(
        calendar: calendar(name: '网课'),
        event: event(
          'ev-${start.millisecondsSinceEpoch}',
          title,
          start.toIso8601String(),
          end.toIso8601String(),
        ),
        start: start,
        end: end,
        sequence: 0,
      );

  Future<void> pumpPoster(
    WidgetTester tester, {
    required List<DateTime> days,
    required List<GeneralEventOccurrence> occurrences,
  }) async {
    // 测试画布足够大，海报（横版 7 天约 2456 宽、约 4200 高）按自然尺寸布局。
    tester.view.physicalSize = const Size(4000, 4500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnconstrainedBox(
            alignment: Alignment.topLeft,
            child: SchedulePoster(days: days, occurrences: occurrences),
          ),
        ),
      ),
    );
  }

  testWidgets('海报以课程表表格展示全部 7 天', (tester) async {
    final start = DateTime(2026, 8, 17);
    final days = [for (var i = 0; i < 7; i++) start.add(Duration(days: i))];
    await pumpPoster(tester, days: days, occurrences: const []);

    expect(find.text('我的日程'), findsOneWidget);
    expect(find.text('AI智能规划网课日程'), findsOneWidget);
    // 表头：时间角标 + 7 天（星期 + 日期）。
    expect(find.text('时间'), findsOneWidget);
    for (final d in days) {
      expect(find.text(weekdays[d.weekday - 1]), findsOneWidget);
      expect(find.text('${d.month}月${d.day}日'), findsOneWidget);
    }
    // 空日程默认时间范围 06:00-23:00，最末刻度 22:00。
    expect(find.text('06:00'), findsOneWidget);
    expect(find.text('22:00'), findsOneWidget);
    expect(find.text('由LinkStudy生成'), findsOneWidget);
  });

  testWidgets('海报将课程放进对应时间的格子', (tester) async {
    final days = [DateTime(2026, 8, 17)];
    final occurrences = [
      occurrence(
        DateTime(2026, 8, 17, 9, 0),
        DateTime(2026, 8, 17, 10, 30),
        title: '高数基础',
      ),
      occurrence(
        DateTime(2026, 8, 17, 19, 0),
        DateTime(2026, 8, 17, 19, 40),
        title: '英语精读',
      ),
    ];
    await pumpPoster(tester, days: days, occurrences: occurrences);

    // 高数基础（90 分钟，格子够高）显示标题 + 起止时间。
    expect(find.text('高数基础'), findsOneWidget);
    expect(find.text('09:00-10:30'), findsOneWidget);
    // 英语精读（40 分钟，格子矮）至少显示标题。
    expect(find.text('英语精读'), findsOneWidget);
    // 时间刻度覆盖 09:00 - 20:00，最末刻度 19:00。
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('19:00'), findsOneWidget);
    expect(find.text('20:00'), findsNothing);
  });

  testWidgets('短课时格子在大字体下不溢出报错', (tester) async {
    // 系统字体放大 1.3 倍时，短课时格子也不能出现 RenderFlex 溢出。
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final days = [DateTime(2026, 8, 17)];
    final occurrences = [
      occurrence(
        DateTime(2026, 8, 17, 9, 0),
        DateTime(2026, 8, 17, 9, 20),
        title: '微积分导论',
      ),
    ];
    await pumpPoster(tester, days: days, occurrences: occurrences);

    expect(find.text('微积分导论'), findsOneWidget);
  });
}
