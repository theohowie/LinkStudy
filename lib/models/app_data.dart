import 'dart:convert';

import '../data/migrations/app_data_migrations.dart';
import '../l10n/app_locale.dart';
import '../utils/constants.dart';
import '../utils/localized_names.dart';
import '../utils/time_utils.dart';
import 'general_schedule.dart';
import 'general_schedule_data.dart';

const Symbol _keepNullable = #keep;

Map<String, dynamic>? _asStringKeyedMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is String) {
      result[key] = entry.value;
    }
  }
  return result;
}

Map<String, dynamic> _decodeJsonObject(String source) {
  final decoded = jsonDecode(source);
  final object = _asStringKeyedMap(decoded);
  if (object == null) {
    throw const FormatException('JSON root must be an object.');
  }
  return object;
}

int? _tryDecodeInt(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

int? _tryDecodeIntegerVersion(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite && value % 1 == 0) {
    return value.toInt();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (RegExp(r'^\d+$').hasMatch(trimmed)) {
      return int.parse(trimmed);
    }
  }
  return null;
}

int? _readOptionalIntegerVersion(
  Map<String, dynamic> json,
  String key, {
  required String errorMessage,
}) {
  if (!json.containsKey(key)) {
    return null;
  }
  final version = _tryDecodeIntegerVersion(json[key]);
  if (version == null || version <= 0) {
    throw FormatException(errorMessage);
  }
  return version;
}

String _stringValue(Object? value, [String fallback = '']) {
  return value is String ? value : fallback;
}

String? _nullableStringValue(Object? value) {
  return value is String ? value : null;
}

class _ThemeSettingsSnapshot {
  const _ThemeSettingsSnapshot({
    required this.themeMode,
    required this.themeColorMode,
    required this.themeSeedColorValue,
    required this.colorfulUiColorValues,
  });

  final String themeMode;
  final String themeColorMode;
  final int themeSeedColorValue;
  final Map<String, int> colorfulUiColorValues;

  _ThemeSettingsSnapshot copyWith({
    String? themeMode,
    String? themeColorMode,
    int? themeSeedColorValue,
    Map<String, int>? colorfulUiColorValues,
  }) {
    return _ThemeSettingsSnapshot(
      themeMode: normalizeThemeMode(themeMode ?? this.themeMode),
      themeColorMode: normalizeThemeColorMode(
        themeColorMode ?? this.themeColorMode,
      ),
      themeSeedColorValue: themeSeedColorValue ?? this.themeSeedColorValue,
      colorfulUiColorValues:
          colorfulUiColorValues ?? this.colorfulUiColorValues,
    );
  }
}

const _modeThemeFieldKeys = {
  'themeMode',
  'themeColorMode',
  'themeSeedColorValue',
  'colorfulUiColorValues',
};

bool _hasModeThemeFields(Map<String, dynamic> json) {
  return _modeThemeFieldKeys.any(json.containsKey);
}

_ThemeSettingsSnapshot _decodeLegacyThemeSettings(Map<String, dynamic> json) {
  return _ThemeSettingsSnapshot(
    themeMode: normalizeThemeMode(
      _stringValue(json['themeMode'], defaultThemeMode),
    ),
    themeColorMode: normalizeThemeColorMode(
      _stringValue(json['themeColorMode'], defaultThemeColorMode),
    ),
    themeSeedColorValue:
        _tryDecodeInt(json['themeSeedColorValue']) ??
        defaultThemeSeedColorValue,
    colorfulUiColorValues: decodeColorValueMap(json['colorfulUiColorValues']),
  );
}

GeneralScheduleData _applyThemeSettingsToGeneralMode(
  GeneralScheduleData data,
  _ThemeSettingsSnapshot theme,
) {
  return data.copyWith(
    themeMode: theme.themeMode,
    themeColorMode: theme.themeColorMode,
    themeSeedColorValue: theme.themeSeedColorValue,
    colorfulUiColorValues: theme.colorfulUiColorValues,
  );
}

List<dynamic> _listValue(Object? value) {
  return value is List ? value : const <dynamic>[];
}

void _validateStorageMapField(Map<String, dynamic> json, String key) {
  if (json.containsKey(key) && _asStringKeyedMap(json[key]) == null) {
    throw FormatException('Stored AppData field "$key" is invalid.');
  }
}

List<Map<String, dynamic>> _storageObjectListField(
  Map<String, dynamic> json,
  String key, {
  required String errorMessage,
}) {
  final raw = json[key];
  if (raw == null) {
    return const [];
  }
  if (raw is! List) {
    throw FormatException(errorMessage);
  }
  final items = raw.map(_asStringKeyedMap).toList();
  if (items.any((item) => item == null)) {
    throw FormatException(errorMessage);
  }
  return items.cast<Map<String, dynamic>>();
}

void _validateStorageIsoDateTimeField(
  Map<String, dynamic> json,
  String key, {
  required String errorMessage,
}) {
  final value = json[key];
  if (value is! String || tryParseStrictIsoDateTime(value) == null) {
    throw FormatException(errorMessage);
  }
}

void _validateStorageGeneralMode(Map<String, dynamic> json) {
  final generalMode = _asStringKeyedMap(json['generalMode']);
  if (generalMode == null) {
    return;
  }
  final schedules = _storageObjectListField(
    generalMode,
    'schedules',
    errorMessage: 'Stored general schedules are invalid.',
  );
  for (final schedule in schedules) {
    final events = _storageObjectListField(
      schedule,
      'events',
      errorMessage: 'Stored general events are invalid.',
    );
    for (final event in events) {
      _validateStorageIsoDateTimeField(
        event,
        'start',
        errorMessage: 'Stored general event dates are invalid.',
      );
      _validateStorageIsoDateTimeField(
        event,
        'end',
        errorMessage: 'Stored general event dates are invalid.',
      );
    }
  }
}

void _validateStorageSnapshotShape(Map<String, dynamic> json) {
  _validateStorageMapField(json, 'generalMode');
  _validateStorageGeneralMode(json);
}

class AppData {
  factory AppData({
    required GeneralScheduleData generalMode,
    String localeCode = defaultLocaleCode,
    String? themeMode,
    String? themeColorMode,
    int? themeSeedColorValue,
    Map<String, int>? colorfulUiColorValues,
    String? privacyPolicyAcceptedVersion,
    String? privacyPolicyAcceptedAtIso,
    String? ignoredUpdateVersion,
    String? availableUpdateVersion,
  }) {
    var nextGeneralMode = generalMode;
    final hasThemeUpdate =
        themeMode != null ||
        themeColorMode != null ||
        themeSeedColorValue != null ||
        colorfulUiColorValues != null;
    if (hasThemeUpdate) {
      final currentTheme = _ThemeSettingsSnapshot(
        themeMode: nextGeneralMode.themeMode,
        themeColorMode: nextGeneralMode.themeColorMode,
        themeSeedColorValue: nextGeneralMode.themeSeedColorValue,
        colorfulUiColorValues: nextGeneralMode.colorfulUiColorValues,
      );
      final updatedTheme = currentTheme.copyWith(
        themeMode: themeMode,
        themeColorMode: themeColorMode,
        themeSeedColorValue: themeSeedColorValue,
        colorfulUiColorValues: colorfulUiColorValues,
      );
      nextGeneralMode = _applyThemeSettingsToGeneralMode(
        nextGeneralMode,
        updatedTheme,
      );
    }
    return AppData._(
      generalMode: nextGeneralMode,
      localeCode: localeCode,
      privacyPolicyAcceptedVersion: privacyPolicyAcceptedVersion,
      privacyPolicyAcceptedAtIso: privacyPolicyAcceptedAtIso,
      ignoredUpdateVersion: ignoredUpdateVersion,
      availableUpdateVersion: availableUpdateVersion,
    );
  }

  const AppData._({
    required this.generalMode,
    this.localeCode = defaultLocaleCode,
    this.privacyPolicyAcceptedVersion,
    this.privacyPolicyAcceptedAtIso,
    this.ignoredUpdateVersion,
    this.availableUpdateVersion,
  });

  final GeneralScheduleData generalMode;
  final String localeCode;
  final String? privacyPolicyAcceptedVersion;
  final String? privacyPolicyAcceptedAtIso;
  final String? ignoredUpdateVersion;
  final String? availableUpdateVersion;

  String get themeMode => generalMode.themeMode;
  String get themeColorMode => generalMode.themeColorMode;
  int get themeSeedColorValue => generalMode.themeSeedColorValue;
  Map<String, int> get colorfulUiColorValues =>
      generalMode.colorfulUiColorValues;

  Map<String, dynamic> toJson() => {
    'schemaVersion': appDataCurrentSchemaVersion,
    'generalMode': generalMode.toJson(),
    'localeCode': normalizeLocaleCode(localeCode),
    if (privacyPolicyAcceptedVersion != null)
      'privacyPolicyAcceptedVersion': privacyPolicyAcceptedVersion,
    if (privacyPolicyAcceptedAtIso != null)
      'privacyPolicyAcceptedAtIso': privacyPolicyAcceptedAtIso,
    if (ignoredUpdateVersion != null)
      'ignoredUpdateVersion': ignoredUpdateVersion,
    if (availableUpdateVersion != null)
      'availableUpdateVersion': availableUpdateVersion,
  };

  factory AppData.fromJson(Map<String, dynamic> json) {
    // Run schemaVersion migrations before any field decoding so legacy data
    // and future bumps are handled in one place instead of being scattered
    // across this fromJson body.
    final migrated = appDataMigrationRunner.run(json);

    final localeCode = normalizeLocaleCode(
      _stringValue(migrated['localeCode'], defaultLocaleCode),
    );

    final legacyThemeSettings = _decodeLegacyThemeSettings(migrated);

    final generalModeJson =
        _asStringKeyedMap(migrated['generalMode']) ?? const {};
    var generalMode = migrated.containsKey('generalMode')
        ? GeneralScheduleData.fromJson(generalModeJson)
        : _buildDefaultGeneralMode();

    if (!_hasModeThemeFields(generalModeJson)) {
      generalMode = _applyThemeSettingsToGeneralMode(
        generalMode,
        legacyThemeSettings,
      );
    }
    return AppData(
      generalMode: generalMode,
      localeCode: localeCode,
      privacyPolicyAcceptedVersion: _nullableStringValue(
        migrated['privacyPolicyAcceptedVersion'],
      ),
      privacyPolicyAcceptedAtIso: _nullableStringValue(
        migrated['privacyPolicyAcceptedAtIso'],
      ),
      ignoredUpdateVersion: _nullableStringValue(
        migrated['ignoredUpdateVersion'],
      ),
      availableUpdateVersion: _nullableStringValue(
        migrated['availableUpdateVersion'],
      ),
    );
  }

  AppData copyWith({
    GeneralScheduleData? generalMode,
    String? localeCode,
    String? themeMode,
    String? themeColorMode,
    int? themeSeedColorValue,
    Map<String, int>? colorfulUiColorValues,
    Object? privacyPolicyAcceptedVersion = _keepNullable,
    Object? privacyPolicyAcceptedAtIso = _keepNullable,
    Object? ignoredUpdateVersion = _keepNullable,
    Object? availableUpdateVersion = _keepNullable,
  }) {
    var nextGeneralMode = generalMode ?? this.generalMode;
    final hasThemeUpdate =
        themeMode != null ||
        themeColorMode != null ||
        themeSeedColorValue != null ||
        colorfulUiColorValues != null;
    if (hasThemeUpdate) {
      final currentTheme = _ThemeSettingsSnapshot(
        themeMode: nextGeneralMode.themeMode,
        themeColorMode: nextGeneralMode.themeColorMode,
        themeSeedColorValue: nextGeneralMode.themeSeedColorValue,
        colorfulUiColorValues: nextGeneralMode.colorfulUiColorValues,
      );
      final updatedTheme = currentTheme.copyWith(
        themeMode: themeMode,
        themeColorMode: themeColorMode,
        themeSeedColorValue: themeSeedColorValue,
        colorfulUiColorValues: colorfulUiColorValues,
      );
      nextGeneralMode = _applyThemeSettingsToGeneralMode(
        nextGeneralMode,
        updatedTheme,
      );
    }
    return AppData(
      generalMode: nextGeneralMode,
      localeCode: normalizeLocaleCode(localeCode ?? this.localeCode),
      privacyPolicyAcceptedVersion:
          identical(privacyPolicyAcceptedVersion, _keepNullable)
          ? this.privacyPolicyAcceptedVersion
          : privacyPolicyAcceptedVersion as String?,
      privacyPolicyAcceptedAtIso:
          identical(privacyPolicyAcceptedAtIso, _keepNullable)
          ? this.privacyPolicyAcceptedAtIso
          : privacyPolicyAcceptedAtIso as String?,
      ignoredUpdateVersion: identical(ignoredUpdateVersion, _keepNullable)
          ? this.ignoredUpdateVersion
          : ignoredUpdateVersion as String?,
      availableUpdateVersion: identical(availableUpdateVersion, _keepNullable)
          ? this.availableUpdateVersion
          : availableUpdateVersion as String?,
    );
  }

  String encode() => jsonEncode(toJson());

  factory AppData.decode(String source) {
    return AppData.fromJson(_decodeJsonObject(source));
  }

  factory AppData.decodeStorageSnapshot(String source) {
    final json = _decodeJsonObject(source);
    final migrated = appDataMigrationRunner.run(json);
    _validateStorageSnapshotShape(migrated);
    return AppData.fromJson(migrated);
  }
}

GeneralScheduleData _buildDefaultGeneralMode() {
  return GeneralScheduleData.createDefault();
}

// Import/Export support

class ImportExportEnvelope {
  const ImportExportEnvelope({
    required this.schema,
    required this.version,
    required this.data,
  });

  final String schema;
  final int version;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {
    'schema': schema,
    'version': version,
    'data': data,
  };

  factory ImportExportEnvelope.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final data = _asStringKeyedMap(rawData);
    if (json.containsKey('data') && data == null) {
      throw const FormatException('Import/export data format is invalid.');
    }
    final version =
        _readOptionalIntegerVersion(
          json,
          'version',
          errorMessage: 'Import/export version is invalid.',
        ) ??
        1;
    return ImportExportEnvelope(
      schema: _stringValue(json['schema']),
      version: version,
      data: data ?? const {},
    );
  }

  String encode() => jsonEncode(toJson());

  factory ImportExportEnvelope.decode(String source) {
    return ImportExportEnvelope.fromJson(_decodeJsonObject(source));
  }
}

void _ensureSupportedEnvelope(
  ImportExportEnvelope envelope, {
  required String expectedSchema,
  String localeCode = defaultLocaleCode,
}) {
  if (!isImportExportSchema(envelope.schema, expectedSchema)) {
    throw FormatException(
      importFileTypeMismatchMessage(localeCode: localeCode),
    );
  }
  if (envelope.version > importExportVersion) {
    throw FormatException(
      importFileVersionUnsupportedMessage(localeCode: localeCode),
    );
  }
}

const _knownImportExportSchemas = {
  appDataSchema,
  generalScheduleDataSchema,
};

String _importExportSchemaSuffix(String schema) {
  final normalized = schema.trim();
  for (final knownSchema in _knownImportExportSchemas) {
    if (normalized == knownSchema || normalized.endsWith('-$knownSchema')) {
      return knownSchema;
    }
  }
  return normalized;
}

bool isImportExportSchema(String schema, String expectedSchema) =>
    _importExportSchemaSuffix(schema) ==
    _importExportSchemaSuffix(expectedSchema);

String encodeAppDataEnvelope(AppData data) {
  return ImportExportEnvelope(
    schema: appDataSchema,
    version: importExportVersion,
    data: data.toJson(),
  ).encode();
}

AppData decodeAppDataEnvelope(
  String source, {
  String localeCode = defaultLocaleCode,
}) {
  final envelope = ImportExportEnvelope.decode(source);
  _ensureSupportedEnvelope(
    envelope,
    expectedSchema: appDataSchema,
    localeCode: localeCode,
  );
  return AppData.fromJson({...envelope.data, 'localeCode': localeCode});
}

AppData buildInitialAppData({String localeCode = defaultLocaleCode}) {
  return AppData(
    generalMode: GeneralScheduleData.createDefault(),
    localeCode: localeCode,
  );
}

enum GeneralScheduleImportMode { addAsNew, replaceActive }

class GeneralScheduleExportData {
  const GeneralScheduleExportData({required this.schedules});

  final List<GeneralSchedule> schedules;

  Map<String, dynamic> toJson() => {
    'schemaVersion': generalScheduleSchemaVersion,
    'schedules': schedules.map((s) => s.toJson()).toList(),
  };

  factory GeneralScheduleExportData.fromJson(Map<String, dynamic> json) {
    final schemaVersion = _readOptionalIntegerVersion(
      json,
      'schemaVersion',
      errorMessage: 'General schedule schemaVersion is invalid.',
    );
    if (schemaVersion != null && schemaVersion > generalScheduleSchemaVersion) {
      throw const FormatException(
        'General schedule schemaVersion is unsupported.',
      );
    }
    final raw = _listValue(json['schedules']);
    final scheduleMaps = raw
        .map(_asStringKeyedMap)
        .whereType<Map<String, dynamic>>()
        .toList();
    final usedScheduleIds = <String>{};
    final schedules = <GeneralSchedule>[];
    for (var i = 0; i < scheduleMaps.length; i++) {
      final schedule = GeneralSchedule.fromJson(scheduleMaps[i]);
      final scheduleId = _normalizeGeneralScheduleImportId(
        schedule.id,
        fallbackPrefix: 'calendar',
        existingIds: usedScheduleIds,
      );
      usedScheduleIds.add(scheduleId);
      schedules.add(
        schedule
            .copyWith(
              id: scheduleId,
              sortOrder: schedule.sortOrder < 0 ? i : schedule.sortOrder,
              events: [
                for (final event in schedule.events)
                  event.copyWith(calendarId: scheduleId),
              ],
            )
            .normalized(sortOrderFallback: i),
      );
    }
    if (raw.isNotEmpty && schedules.isEmpty) {
      throw const FormatException('General schedule JSON format is invalid.');
    }
    return GeneralScheduleExportData(schedules: schedules);
  }
}

String _normalizeGeneralScheduleImportId(
  String rawId, {
  required String fallbackPrefix,
  required Set<String> existingIds,
}) {
  final sanitized = _sanitizeGeneralScheduleImportId(rawId);
  final candidate = sanitized.isEmpty ? fallbackPrefix : sanitized;
  if (!existingIds.contains(candidate)) {
    return candidate;
  }
  final base = sanitized.isEmpty
      ? fallbackPrefix
      : _copyImportIdBase(sanitized);
  var next = base;
  var suffix = 1;
  while (existingIds.contains(next)) {
    next = '${base}_${suffix++}';
  }
  return next;
}

String _sanitizeGeneralScheduleImportId(String rawId) {
  final source = rawId.trim();
  if (source.isEmpty) {
    return '';
  }
  final safe = source
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (safe.isEmpty) {
    return '';
  }
  return safe.length > 96 ? safe.substring(0, 96) : safe;
}

String _copyImportIdBase(String id) {
  final match = RegExp(r'^(.*_copy)(?:_\d+)?$').firstMatch(id);
  return match == null ? '${id}_copy' : match.group(1)!;
}

String encodeGeneralScheduleDataEnvelope(GeneralScheduleExportData data) {
  return ImportExportEnvelope(
    schema: generalScheduleDataSchema,
    version: importExportVersion,
    data: data.toJson(),
  ).encode();
}

GeneralScheduleExportData decodeGeneralScheduleDataEnvelope(
  String source, {
  String localeCode = defaultLocaleCode,
}) {
  final envelope = ImportExportEnvelope.decode(source);
  _ensureSupportedEnvelope(
    envelope,
    expectedSchema: generalScheduleDataSchema,
    localeCode: localeCode,
  );
  return GeneralScheduleExportData.fromJson(envelope.data);
}
