import '../models/general_models.dart';
import '../models/app_data.dart';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';

import '../data/app_repository.dart';
import '../data/timetable_storage.dart';
import '../l10n/app_locale.dart' as app_locale;
import '../services/general_calendar_service.dart';
import '../services/general_calendar_ics_service.dart';
import '../services/general_occurrence_service.dart';
import '../services/import_export_service.dart';
import '../services/privacy_service.dart';
import '../services/settings_service.dart';
import '../utils/localized_names.dart';

part 'timetable_provider_general.dart';
part 'timetable_provider_import_export.dart';
part 'timetable_provider_lifecycle.dart';
part 'timetable_provider_settings.dart';

const _calendarService = GeneralCalendarService();
const _occurrenceService = GeneralOccurrenceService();
const _importExportService = ImportExportService();

enum AppImportMode { replaceAll, addAll }

String resolveFirstLaunchLocaleCode(Locale? locale) {
  return app_locale.resolveFirstLaunchLocaleCode(locale);
}

String _defaultSystemLocaleCodeResolver() {
  final locales = PlatformDispatcher.instance.locales;
  return app_locale.resolveFirstLaunchLocaleCode(
    locales.isEmpty ? null : locales.first,
  );
}

abstract class _TimetableProviderBase extends ChangeNotifier {
  AppData get _appData;
  set _appData(AppData value);

  bool get _isLoaded;
  set _isLoaded(bool value);

  bool get _isLoading;
  set _isLoading(bool value);

  set _storagePath(String? value);

  AppRepository get _repository;
  String Function() get _systemLocaleCodeResolver;
  SettingsService get _settings;
  PrivacyService get _privacy;

  GeneralSchedule? get activeGeneralScheduleOrNull;

  Future<AppData> _buildDefaultAppData();
  Future<void> _saveAndNotify();
  Future<void> _save();
}

class TimetableProvider extends _TimetableProviderBase
    with
        _TimetableProviderGeneral,
        _TimetableProviderImportExport,
        _TimetableProviderLifecycle,
        _TimetableProviderSettings {
  TimetableProvider({
    TimetableStorage? storage,
    AppRepository? repository,
    String Function()? systemLocaleCodeResolver,
    SettingsService? settingsService,
    PrivacyService? privacyService,
  }) : _repository =
           repository ?? AppRepository(storage: storage ?? TimetableStorage()),
       _systemLocaleCodeResolver =
           systemLocaleCodeResolver ?? _defaultSystemLocaleCodeResolver,
       _settings = settingsService ?? const SettingsService(),
       _privacy = privacyService ?? const PrivacyService();

  @override
  final AppRepository _repository;
  @override
  final String Function() _systemLocaleCodeResolver;
  @override
  final SettingsService _settings;
  @override
  final PrivacyService _privacy;

  @override
  AppData _appData = buildInitialAppData();
  @override
  bool _isLoaded = false;
  @override
  bool _isLoading = false;
  @override
  String? _storagePath;

  bool get isLoaded => _isLoaded;
  String? get storagePath => _storagePath;

  RecoveryStatus get lastRecoveryStatus => _repository.lastRecoveryStatus;
  String get localeCode => _appData.localeCode;
  String get themeMode => _appData.generalMode.themeMode;
  String get themeColorMode => _appData.generalMode.themeColorMode;
  int get themeSeedColorValue => _appData.generalMode.themeSeedColorValue;
  Map<String, int> get colorfulUiColorValues =>
      _appData.generalMode.colorfulUiColorValues;

  GeneralScheduleData get generalMode => _appData.generalMode;

  String? get ignoredUpdateVersion => _appData.ignoredUpdateVersion;
  String? get availableUpdateVersion => _appData.availableUpdateVersion;

  @override
  Future<void> _saveAndNotify() async {
    final previous = _repository.current;
    try {
      await _save();
    } catch (_) {
      if (previous != null) {
        _appData = previous;
      }
      notifyListeners();
      rethrow;
    }
    notifyListeners();
  }

  @override
  Future<void> _save() async {
    final normalized = _importExportService.normalizeAppData(
      _appData,
      localeCode: _appData.localeCode,
    );
    await _repository.save(normalized);
    _appData = normalized;
  }
}
