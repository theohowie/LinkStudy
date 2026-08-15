// LinkStudy — 悬浮窗网课课程表
//
// LinkStudy is a derivative work of Sked (https://github.com/Mashiro0619/Sked),
// Copyright (c) Mashiro0619, licensed under the GNU Affero General Public
// License v3.0 (AGPL-3.0). Modifications: Copyright (c) TheoHowie.
// Both the original work and this derivative are licensed under AGPL-3.0.
// See LICENSE and NOTICE for details.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme/app_theme.dart';
import 'l10n/app_locale.dart';
import 'l10n/app_localizations.dart';
import 'courses/course_ingest_service.dart';
import 'courses/link_course.dart';
import 'courses/link_study_grid_sync.dart';
import 'platform/overlay_client.dart';
import 'providers/timetable_provider.dart';
import 'screens/app_home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  _registerLicenses();
  // 悬浮窗（LinkStudy 移植）：设置页开关开启后，启动时恢复悬浮球与已保存的样式；订阅采集事件（预留课程落库接入点）
  final overlayClient = OverlayClient();
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(overlayPrefsEnabledKey) ?? false) {
    if (await overlayClient.isPermissionGranted()) {
      unawaited(overlayClient.startOverlay());
      unawaited(
        overlayClient.setOverlayStyle(
          prefs.getString(overlayPrefsStyleKey) ?? overlayStyleCapsuleBlack,
        ),
      );
      unawaited(
        overlayClient.setOverlayOpacity(
          prefs.getInt(overlayPrefsOpacityKey) ?? 100,
        ),
      );
    }
  }
  // LinkStudy 课程入库：加载课程存储，悬浮窗面板保存的草稿经接口类解析校验后写入本地课程表。
  // EventChannel 只订阅一次，按 type 分发（多次订阅会导致原生侧 sink 覆盖、事件丢失）。
  final courseStore = LinkCourseStore.instance;
  await courseStore.ensureLoaded();
  final ingestService = CourseIngestService(store: courseStore);
  overlayClient.events.listen((raw) async {
    if (raw is! Map) return;
    final type = raw['type'];
    switch (type) {
      case 'onDraftSaved':
        final url = raw['url'] as String? ?? '';
        final title = raw['title'] as String? ?? '';
        final duration = (raw['durationMinutes'] as num?)?.toInt() ?? 0;
        debugPrint('[linkstudy] overlay draft: $url | $title | ${duration}min');
        final result = await ingestService.ingest(
          CourseDraft(url: url, title: title, durationMinutes: duration),
        );
        if (result.success) {
          final c = result.course!;
          debugPrint('[linkstudy] course saved: ${c.title} (${c.url}) ${c.durationMinutes}min');
        } else {
          debugPrint('[linkstudy] ingest rejected: ${result.error}');
        }
      case 'onUrlsCaptured':
        debugPrint('[linkstudy] captured urls: ${raw['urls']}');
      case 'onOverlayTapped':
        debugPrint('[linkstudy] overlay tapped');
    }
  });
  final provider = TimetableProvider();
  unawaited(provider.load());
  // LinkStudy 课表 → 首页日程网格：provider 加载完成后同步一次，课程/槽位变化时重新同步
  final gridSync = LinkStudyGridSync(provider: provider, store: courseStore);
  var gridSynced = false;
  provider.addListener(() {
    if (provider.isLoaded && !gridSynced) {
      gridSynced = true;
      unawaited(gridSync.sync());
    }
  });
  courseStore.addListener(() {
    if (provider.isLoaded) {
      unawaited(gridSync.sync());
    }
  });
  runApp(MyApp(provider: provider));
}

void _registerLicenses() {
  LicenseRegistry.addLicense(() async* {
    final notice = await rootBundle.loadString('NOTICE');
    yield LicenseEntryWithLineBreaks(['App icon assets'], notice);
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.provider});

  final TimetableProvider provider;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TimetableProvider>.value(
      value: provider,
      child: Consumer<TimetableProvider>(
        builder: (context, timetableProvider, child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
            locale: appLocaleFromCode(timetableProvider.localeCode),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            themeMode: themeModeFromValue(timetableProvider.themeMode),
            themeAnimationStyle: appThemeAnimationStyle,
            theme: buildAppTheme(
              seedColor: Color(timetableProvider.themeSeedColorValue),
              brightness: Brightness.light,
              themeColorMode: timetableProvider.themeColorMode,
              colorfulUiColorValues: timetableProvider.colorfulUiColorValues,
            ),
            darkTheme: buildAppTheme(
              seedColor: Color(timetableProvider.themeSeedColorValue),
              brightness: Brightness.dark,
              themeColorMode: timetableProvider.themeColorMode,
              colorfulUiColorValues: timetableProvider.colorfulUiColorValues,
            ),
            home: const AppHomeScreen(),
            builder: (context, child) {
              // 把当前 Material 3 主题色下发给原生悬浮填写面板（明暗/自定义色变化时自动同步）
              final scheme = Theme.of(context).colorScheme;
              unawaited(
                OverlayClient().setPanelColors({
                  'primary': scheme.primary.toARGB32(),
                  'onPrimary': scheme.onPrimary.toARGB32(),
                  'surface': scheme.surface.toARGB32(),
                  'onSurface': scheme.onSurface.toARGB32(),
                  'onSurfaceVariant': scheme.onSurfaceVariant.toARGB32(),
                  'outline': scheme.outline.toARGB32(),
                }),
              );
              return child!;
            },
          );
        },
      ),
    );
  }
}
