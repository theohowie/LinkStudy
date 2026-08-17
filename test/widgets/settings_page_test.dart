import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:linkstudy/data/timetable_storage.dart';
import 'package:linkstudy/l10n/app_locale.dart';
import 'package:linkstudy/l10n/app_localizations.dart';
import 'package:linkstudy/models/app_data.dart';
import 'package:linkstudy/providers/timetable_provider.dart';
import 'package:linkstudy/screens/settings_page.dart';
import 'package:linkstudy/screens/theme_settings_page.dart';
import 'package:linkstudy/services/privacy_service.dart';
import 'package:linkstudy/widgets/expressive_motion.dart';
import 'package:linkstudy/widgets/text_transfer_widgets.dart';

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
  Future<String?> filePath() async => 'memory://settings-test';
}

class _NoopPrivacyService extends PrivacyService {
  const _NoopPrivacyService();

  @override
  Future<String?> fetchCurrentPrivacyPolicyVersion() async => null;
}


AppData _buildGeneralData() {
  return buildInitialAppData(localeCode: defaultLocaleCode);
}

Future<TimetableProvider> _createProvider(AppData data) async {
  final provider = TimetableProvider(
    storage: _MemoryTimetableStorage(data),
    systemLocaleCodeResolver: () => defaultLocaleCode,
    privacyService: const _NoopPrivacyService(),
  );
  await provider.load();
  return provider;
}

Future<void> _pumpSettingsPage(
  WidgetTester tester,
  TimetableProvider provider,
) async {
  PackageInfo.setMockInitialValues(
    appName: 'LinkStudy',
    packageName: 'com.theohowie.linkstudy',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<TimetableProvider>.value(
      value: provider,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpSettingsHostPage(
  WidgetTester tester,
  TimetableProvider provider,
) async {
  PackageInfo.setMockInitialValues(
    appName: 'LinkStudy',
    packageName: 'com.theohowie.linkstudy',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<TimetableProvider>.value(
      value: provider,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ChangeNotifierProvider<TimetableProvider>.value(
                              value: provider,
                              child: const SettingsPage(),
                            ),
                      ),
                    );
                  },
                  child: const Text('Open settings host'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpRouteTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('general settings page groups entries into sections', (
    tester,
  ) async {
    final provider = await _createProvider(_buildGeneralData());
    await _pumpSettingsPage(tester, provider);

    expect(find.text('General schedule'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Timetable'), findsNothing);
    expect(find.text('General display settings'), findsOneWidget);
    expect(find.text('Schedule import & export'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('App'), 120);
    expect(find.text('App'), findsOneWidget);
  });

  testWidgets('app backup entry opens restore and export actions', (
    tester,
  ) async {
    final provider = await _createProvider(_buildGeneralData());
    await _pumpSettingsPage(tester, provider);

    await tester.scrollUntilVisible(find.text('App backup and restore'), 120);
    await tester.tap(find.text('App backup and restore'));
    await tester.pumpAndSettle();

    expect(find.text('Restore from JSON file'), findsOneWidget);
    expect(find.text('Paste backup JSON'), findsOneWidget);
    expect(find.text('Share backup file'), findsOneWidget);
    expect(find.text('Save backup file'), findsOneWidget);
    expect(find.text('Copy backup text'), findsOneWidget);
    expect(
      find.textContaining('are not written to backup files'),
      findsOneWidget,
    );
  });

  testWidgets('theme settings entry ignores rapid duplicate taps', (
    tester,
  ) async {
    // 设置页含 AI 排课分组后内容变长，放大视口确保 Theme 项可见。
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final provider = await _createProvider(_buildGeneralData());
    await _pumpSettingsPage(tester, provider);

    final themeTile = find.text('Theme');
    expect(themeTile, findsOneWidget);

    await tester.tap(themeTile);
    await tester.tap(themeTile, warnIfMissed: false);
    await _pumpRouteTransition(tester);

    expect(find.byType(ThemeSettingsPage, skipOffstage: false), findsOneWidget);
  });

  testWidgets('general import/export actions ignore rapid duplicate taps', (
    tester,
  ) async {
    final provider = await _createProvider(_buildGeneralData());
    await _pumpSettingsPage(tester, provider);

    final importExportTile = find.text('Schedule import & export');
    expect(importExportTile, findsOneWidget);

    await tester.tap(importExportTile);
    await tester.tap(importExportTile, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Import JSON file'), findsOneWidget);
  });

  testWidgets('general data action chevrons are vertically centered', (
    tester,
  ) async {
    final provider = await _createProvider(_buildGeneralData());
    await _pumpSettingsPage(tester, provider);

    await tester.tap(find.text('Schedule import & export'));
    await tester.pumpAndSettle();

    final actionTitles = [
      'Import JSON file',
      'Paste JSON',
      'Import ICS file',
      'Paste ICS',
    ];
    for (final title in actionTitles) {
      final titleFinder = find.text(title);
      expect(titleFinder, findsOneWidget);

      final tileBox = tester.renderObject<RenderBox>(
        find.ancestor(of: titleFinder, matching: find.byType(ExpressiveTap)),
      );
      final chevronFinder = find.descendant(
        of: find.ancestor(
          of: titleFinder,
          matching: find.byType(ExpressiveTap),
        ),
        matching: find.byIcon(Icons.chevron_right),
      );
      final chevronBox = tester.renderObject<RenderBox>(chevronFinder);
      final tileCenterY = tileBox
          .localToGlobal(tileBox.size.center(Offset.zero))
          .dy;
      final chevronCenterY = chevronBox
          .localToGlobal(chevronBox.size.center(Offset.zero))
          .dy;

      expect((chevronCenterY - tileCenterY).abs(), lessThanOrEqualTo(1.0));
    }
  });

  testWidgets('general data sheet action ignores rapid duplicate taps', (
    tester,
  ) async {
    final provider = await _createProvider(_buildGeneralData());
    await _pumpSettingsHostPage(tester, provider);

    await tester.tap(find.text('Open settings host'));
    await _pumpRouteTransition(tester);

    final importExportTile = find.text('Schedule import & export');
    expect(importExportTile, findsOneWidget);

    await tester.tap(importExportTile);
    await tester.pumpAndSettle();

    final pasteJsonAction = find.text('Paste JSON');
    expect(pasteJsonAction, findsOneWidget);

    await tester.tap(pasteJsonAction);
    await tester.tap(pasteJsonAction, warnIfMissed: false);
    await _pumpRouteTransition(tester);

    expect(find.byType(TextImportPage), findsOneWidget);
    expect(find.byType(TextImportPage, skipOffstage: false), findsOneWidget);
    expect(find.text('Open settings host'), findsNothing);
    expect(
      find.text('Open settings host', skipOffstage: false),
      findsOneWidget,
    );
  });
}