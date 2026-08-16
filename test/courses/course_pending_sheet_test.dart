import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkstudy/courses/link_course.dart';
import 'package:linkstudy/widgets/course_pending_sheet.dart';

Future<void> _pumpSheet(WidgetTester tester, LinkCourseStore store) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: CoursePendingSheet(store: store)),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    // FakeAsync 环境下真实文件 I/O 会挂起，跳过持久化。
    LinkCourseStore.instance.debugSkipPersist = true;
  });

  testWidgets('展示未排课课程卡片：名称/时长/链接', (tester) async {
    final store = LinkCourseStore.instance;
    store.debugClear();
    await store.addCourse(
      url: 'https://example.com/1',
      title: '考研英语',
      durationMinutes: 45,
    );
    await _pumpSheet(tester, store);

    expect(find.text('考研英语'), findsOneWidget);
    expect(find.text('45 分钟'), findsOneWidget);
    expect(find.text('https://example.com/1'), findsOneWidget);
    expect(find.textContaining('未排课课程（1）'), findsOneWidget);
  });

  testWidgets('勾选后可点下一步并返回所选课程 id', (tester) async {
    final store = LinkCourseStore.instance;
    store.debugClear();
    final a = await store.addCourse(
      url: 'https://example.com/a',
      title: '课程A',
      durationMinutes: 40,
    );
    await store.addCourse(
      url: 'https://example.com/b',
      title: '课程B',
      durationMinutes: 40,
    );
    await _pumpSheet(tester, store);

    final nextButton = find.widgetWithText(FilledButton, '下一步');
    expect(
      tester.widget<FilledButton>(nextButton).onPressed,
      isNull,
      reason: '未勾选时下一步禁用',
    );

    // 点第一张卡片（课程A）勾选。
    await tester.tap(find.text('课程A'));
    await tester.pump();

    final enabledButton = tester.widget<FilledButton>(nextButton);
    expect(enabledButton.onPressed, isNotNull);

    // 点下一步 → 返回勾选的 id。
    final result = <List<String>>[];
    // 重新以可捕获结果的方式 pump。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  final selected = await showModalBottomSheet<List<String>>(
                    context: context,
                    builder: (_) => CoursePendingSheet(store: store),
                  );
                  result.add(selected ?? const []);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课程A'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '下一步'));
    await tester.pumpAndSettle();
    expect(result, hasLength(1));
    expect(result.single, [a.id]);
  });

  testWidgets('全选与取消全选', (tester) async {
    final store = LinkCourseStore.instance;
    store.debugClear();
    await store.addCourse(
      url: 'https://example.com/a',
      title: '课程A',
      durationMinutes: 40,
    );
    await store.addCourse(
      url: 'https://example.com/b',
      title: '课程B',
      durationMinutes: 40,
    );
    await _pumpSheet(tester, store);

    // 全选 → 下一步可用。
    await tester.tap(find.text('全选'));
    await tester.pump();
    final nextButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '下一步'),
    );
    expect(nextButton.onPressed, isNotNull);

    // 取消全选 → 禁用。
    await tester.tap(find.text('取消全选'));
    await tester.pump();
    final disabledButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '下一步'),
    );
    expect(disabledButton.onPressed, isNull);
  });

  testWidgets('删除勾选课程（带确认弹窗）', (tester) async {
    final store = LinkCourseStore.instance;
    store.debugClear();
    await store.addCourse(
      url: 'https://example.com/del',
      title: '待删课程',
      durationMinutes: 40,
    );
    await _pumpSheet(tester, store);

    await tester.tap(find.text('待删课程'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('删除课程'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(store.courses, isEmpty);
    expect(find.textContaining('未排课课程（0）'), findsOneWidget);
    expect(find.text('暂无未排课课程，先去悬浮窗采集一些吧'), findsOneWidget);
  });

  testWidgets('手动添加课程入池（不依赖悬浮窗）', (tester) async {
    final store = LinkCourseStore.instance;
    store.debugClear();
    await _pumpSheet(tester, store);

    expect(find.text('暂无未排课课程，先去悬浮窗采集一些吧'), findsOneWidget);

    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(find.text('添加课程'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).at(0),
      'https://example.com/manual',
    );
    await tester.enterText(find.byType(TextField).at(1), '手动课程');
    await tester.enterText(find.byType(TextField).at(2), '30');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(store.courses, hasLength(1));
    expect(store.pendingCount, 1);
    expect(find.text('手动课程'), findsOneWidget);
    expect(find.text('30 分钟'), findsOneWidget);
  });

  testWidgets('手动添加课程：URL 选填，名称+时长必填', (tester) async {
    final store = LinkCourseStore.instance;
    store.debugClear();
    await _pumpSheet(tester, store);

    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(find.text('添加课程'), findsOneWidget);

    // 只填名称+时长（URL 留空）可保存。
    await tester.enterText(find.byType(TextField).at(0), '');
    await tester.enterText(find.byType(TextField).at(1), '无链接课程');
    await tester.enterText(find.byType(TextField).at(2), '30');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(store.courses, hasLength(1));
    expect(store.courses.single.title, '无链接课程');
    expect(store.courses.single.url, isEmpty);
    expect(find.text('无链接课程'), findsOneWidget);

    // 名称必填：留空时提示。
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).at(0),
      'https://example.com/no-title',
    );
    await tester.enterText(find.byType(TextField).at(1), '');
    await tester.enterText(find.byType(TextField).at(2), '30');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();
    expect(find.text('请填写课程名称'), findsOneWidget);
    expect(store.courses, hasLength(1), reason: '名称为空不应入库');
  });

  testWidgets('无课程时全选与下一步禁用', (tester) async {
    final store = LinkCourseStore.instance;
    store.debugClear();
    await _pumpSheet(tester, store);

    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '全选'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '下一步'))
          .onPressed,
      isNull,
    );
  });
}
