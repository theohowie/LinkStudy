import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:linkstudy/data/timetable_storage.dart';
import 'package:linkstudy/l10n/app_locale.dart';
import 'package:linkstudy/l10n/app_localizations.dart';
import 'package:linkstudy/models/app_data.dart';
import 'package:linkstudy/models/general_models.dart';
import 'package:linkstudy/providers/timetable_provider.dart';
import 'package:linkstudy/screens/general_display_settings_page.dart';
import 'package:linkstudy/widgets/sked_dropdown_menu.dart';

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
  Future<String?> filePath() async => 'memory://general-display-settings-test';
}

Future<TimetableProvider> _createProvider() async {
  final provider = TimetableProvider(
    storage: _MemoryTimetableStorage(
      buildInitialAppData(localeCode: defaultLocaleCode),
    ),
    systemLocaleCodeResolver: () => defaultLocaleCode,
  );
  await provider.load();
  return provider;
}

Future<void> _pumpPage(WidgetTester tester, TimetableProvider provider) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<TimetableProvider>.value(
      value: provider,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GeneralDisplaySettingsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows default view as a setting instead of page tabs', (
    tester,
  ) async {
    // 页面含固定时间段设置后内容变长，放大视口确保底部项可见。
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final provider = await _createProvider();

    await _pumpPage(tester, provider);

    expect(find.text('Startup'), findsOneWidget);
    expect(find.text('Default view'), findsOneWidget);
    expect(find.text('Schedule display'), findsOneWidget);
    expect(find.text('Time grid'), findsOneWidget);
    expect(find.text('Popup behavior'), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsNothing);
    expect(find.byType(SkedDropdownMenu<String>), findsOneWidget);

    await tester.tap(find.byType(SkedDropdownMenu<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Month').last);
    await tester.pumpAndSettle();

    expect(provider.generalDefaultView, generalViewMonth);
  });

  testWidgets('default view dropdown opens with a full field-width menu', (
    tester,
  ) async {
    final provider = await _createProvider();

    await _pumpPage(tester, provider);

    final dropdown = find.byType(SkedDropdownMenu<String>);
    final dropdownRect = tester.getRect(dropdown);

    await tester.tap(dropdown);
    await tester.pumpAndSettle();

    final firstMenuItem = find
        .ancestor(
          of: find.text('Week').last,
          matching: find.byType(MenuItemButton),
        )
        .first;
    final menuItemRect = tester.getRect(firstMenuItem);

    expect(menuItemRect.left, closeTo(dropdownRect.left, 1));
    expect(menuItemRect.width, greaterThanOrEqualTo(dropdownRect.width - 16));
  });

  testWidgets('固定无法安排日程时间段：添加、编辑、删除', (tester) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final provider = await _createProvider();

    await _pumpPage(tester, provider);

    // 初始为空。
    expect(find.text('固定无法安排日程时间段'), findsOneWidget);
    expect(find.text('暂无固定时间段'), findsOneWidget);

    // 添加：默认 12:00-13:00，输入名称后确定。
    await tester.tap(find.text('添加时间段'));
    await tester.pumpAndSettle();
    expect(find.text('添加时间段'), findsWidgets);
    // 页面本身还有时间精度的数字输入框，取弹窗里最后一个 TextField。
    await tester.enterText(find.byType(TextField).last, '午饭');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(provider.generalFixedBlocks, hasLength(1));
    expect(provider.generalFixedBlocks.single.label, '午饭');
    expect(provider.generalFixedBlocks.single.startMinute, 12 * 60);
    expect(provider.generalFixedBlocks.single.endMinute, 13 * 60);
    expect(find.text('午饭'), findsOneWidget);
    expect(find.text('12:00 - 13:00'), findsOneWidget);

    // 编辑：点击条目打开弹窗，取消不修改。
    await tester.tap(find.text('午饭'));
    await tester.pumpAndSettle();
    expect(find.text('编辑时间段'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(provider.generalFixedBlocks, hasLength(1));

    // 删除。
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(provider.generalFixedBlocks, isEmpty);
    expect(find.text('暂无固定时间段'), findsOneWidget);
  });
}
