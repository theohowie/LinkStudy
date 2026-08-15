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
  overlayClient.draftsSaved.listen((d) {
    debugPrint('[overlay] draft saved: ${d.url} | ${d.title} | ${d.durationMinutes}min');
  });
  overlayClient.capturedUrls.listen((urls) {
    debugPrint('[overlay] captured urls: $urls');
  });
  overlayClient.overlayTapped.listen((_) {
    debugPrint('[overlay] tapped');
  });
  final provider = TimetableProvider();
  unawaited(provider.load());
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
