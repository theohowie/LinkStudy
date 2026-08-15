import 'dart:convert';

import '../l10n/app_locale.dart' as app_locale;
import '../models/app_data.dart';
import '../models/general_event.dart';
import '../models/general_event_occurrence.dart';
import '../models/general_schedule.dart';
import '../models/general_schedule_data.dart';
import '../utils/import_id_sanitizer.dart';
import '../utils/localized_names.dart';
import '../utils/time_utils.dart';
import 'general_calendar_ics_service.dart';

class GeneralScheduleImportResult {
  const GeneralScheduleImportResult({
    required this.importedCount,
    required this.scheduleNames,
    this.icsWarnings = const [],
  });

  final int importedCount;
  final List<String> scheduleNames;
  final List<GeneralCalendarIcsImportWarning> icsWarnings;

  bool get hasWarnings => icsWarnings.isNotEmpty;
}

class GeneralScheduleImportMutation {
  const GeneralScheduleImportMutation({
    required this.data,
    required this.result,
  });

  final GeneralScheduleData data;
  final GeneralScheduleImportResult result;
}

/// Import/export transformations that are independent from provider state.
class ImportExportService {
  const ImportExportService({
    GeneralCalendarIcsService icsService = const GeneralCalendarIcsService(),
  }) : _icsService = icsService;

  final GeneralCalendarIcsService _icsService;

  String exportAppDataJson(AppData data) => encodeAppDataEnvelope(data);

  AppData normalizeAppData(AppData data, {required String localeCode}) {
    return data.copyWith(
      localeCode: app_locale.normalizeLocaleCode(data.localeCode),
      generalMode: _normalizeGeneralScheduleData(data.generalMode),
    );
  }

  String exportSelectedGeneralSchedulesJson(
    GeneralScheduleData data,
    List<String> scheduleIds, {
    required String localeCode,
  }) {
    final selected = _selectedSchedules(data, scheduleIds);
    if (selected.isEmpty) {
      throw FormatException(
        selectAtLeastOneScheduleMessage(localeCode: localeCode),
      );
    }
    return encodeGeneralScheduleDataEnvelope(
      GeneralScheduleExportData(schedules: selected),
    );
  }

  String exportSelectedGeneralSchedulesIcs(
    GeneralScheduleData data,
    List<String> scheduleIds, {
    required String localeCode,
  }) {
    final selected = _selectedSchedules(data, scheduleIds);
    if (selected.isEmpty) {
      throw FormatException(
        selectAtLeastOneScheduleMessage(localeCode: localeCode),
      );
    }
    return _icsService.exportSchedules(selected);
  }

  List<GeneralSchedule> previewImportGeneralSchedules(
    String source, {
    required String localeCode,
  }) {
    final decoded = decodeGeneralScheduleDataEnvelope(
      source,
      localeCode: localeCode,
    );
    if (decoded.schedules.isEmpty) {
      throw FormatException(noSchedulesInImportMessage(localeCode: localeCode));
    }
    return decoded.schedules;
  }

  GeneralCalendarIcsImportResult previewImportGeneralSchedulesIcs(
    String source, {
    required String localeCode,
  }) {
    try {
      return _icsService.importSchedules(source);
    } on GeneralCalendarIcsImportException catch (error) {
      throw FormatException(
        _generalIcsImportErrorMessage(error.code, localeCode),
      );
    }
  }

  GeneralScheduleImportMutation importSelectedGeneralSchedulesJson(
    GeneralScheduleData data,
    String source, {
    required List<String> scheduleIds,
    required GeneralScheduleImportMode mode,
    required String localeCode,
  }) {
    final imported = decodeGeneralScheduleDataEnvelope(
      source,
      localeCode: localeCode,
    );
    final selected = _selectImportedSchedules(
      imported.schedules,
      scheduleIds,
      localeCode: localeCode,
    );
    return _mergeGeneralSchedules(
      data,
      selected,
      mode: mode,
      localeCode: localeCode,
    );
  }

  GeneralScheduleImportMutation importGeneralSchedulesIcs(
    GeneralScheduleData data,
    String source, {
    required GeneralScheduleImportMode mode,
    required String localeCode,
  }) {
    final imported = previewImportGeneralSchedulesIcs(
      source,
      localeCode: localeCode,
    );
    if (imported.schedules.isEmpty) {
      throw FormatException(noSchedulesInImportMessage(localeCode: localeCode));
    }
    return _mergeGeneralSchedules(
      data,
      imported.schedules,
      mode: mode,
      localeCode: localeCode,
      icsWarnings: imported.warningItems,
    );
  }

  List<GeneralSchedule> _selectedSchedules(
    GeneralScheduleData data,
    List<String> scheduleIds,
  ) {
    final selectedIdSet = scheduleIds.toSet();
    return data.schedules.where((s) => selectedIdSet.contains(s.id)).toList();
  }

  List<GeneralSchedule> _selectImportedSchedules(
    List<GeneralSchedule> imported,
    List<String> scheduleIds, {
    required String localeCode,
  }) {
    final selectedIdSet = scheduleIds.map((id) => id.trim()).toSet();
    final selected = imported
        .where(
          (schedule) => selectedIdSet.any(
            (requestedId) =>
                _matchesImportedGeneralScheduleId(schedule.id, requestedId),
          ),
        )
        .toList();
    if (selected.isEmpty) {
      throw FormatException(
        selectAtLeastOneScheduleMessage(localeCode: localeCode),
      );
    }
    return selected;
  }

  GeneralScheduleImportMutation _mergeGeneralSchedules(
    GeneralScheduleData data,
    List<GeneralSchedule> selected, {
    required GeneralScheduleImportMode mode,
    required String localeCode,
    List<GeneralCalendarIcsImportWarning> icsWarnings = const [],
  }) {
    if (mode == GeneralScheduleImportMode.replaceActive) {
      if (selected.length != 1) {
        throw FormatException(
          replaceActiveRequiresSingleScheduleMessage(localeCode: localeCode),
        );
      }
      final current = data.activeScheduleOrNull;
      if (current == null) {
        throw FormatException(
          noActiveScheduleToReplaceMessage(localeCode: localeCode),
        );
      }
      final existingEventIds = _generalEventIds(
        data.schedules.where((schedule) => schedule.id != current.id),
      );
      final replaced = _sanitizeImportedGeneralSchedule(
        selected.first,
        scheduleId: current.id,
        existingEventIds: existingEventIds,
      );
      final updated = data
          .copyWith(
            reminderAcknowledgements: data.reminderAcknowledgements
                .where(
                  (item) => !_reminderKeyBelongsToSchedule(
                    item.occurrenceKey,
                    current,
                  ),
                )
                .toList(),
          )
          .withSchedule(replaced);
      return GeneralScheduleImportMutation(
        data: updated,
        result: GeneralScheduleImportResult(
          importedCount: 1,
          scheduleNames: [replaced.name],
          icsWarnings: icsWarnings,
        ),
      );
    }

    final existingIds = data.schedules.map((s) => s.id).toSet();
    final existingEventIds = _generalEventIds(data.schedules);
    final existingEventContentKeys = _generalEventContentKeys(data.schedules);
    final appended = <GeneralSchedule>[];
    for (final schedule in selected) {
      final nextId = _normalizeImportedGeneralId(
        schedule.id,
        fallbackPrefix: 'schedule_import',
        existingIds: existingIds,
      );
      existingIds.add(nextId);
      final sanitized = _sanitizeImportedGeneralSchedule(
        schedule,
        scheduleId: nextId,
        existingEventIds: existingEventIds,
      );
      final uniqueEvents = _uniqueImportedGeneralEvents(
        sanitized,
        existingEventContentKeys,
      );
      if (sanitized.events.isNotEmpty && uniqueEvents.isEmpty) {
        continue;
      }
      appended.add(sanitized.copyWith(events: uniqueEvents));
    }
    if (appended.isEmpty) {
      return GeneralScheduleImportMutation(
        data: data,
        result: GeneralScheduleImportResult(
          importedCount: 0,
          scheduleNames: const [],
          icsWarnings: icsWarnings,
        ),
      );
    }
    final updated = data.copyWith(
      schedules: [...data.schedules, ...appended],
      activeScheduleId: appended.last.id,
    );
    return GeneralScheduleImportMutation(
      data: updated,
      result: GeneralScheduleImportResult(
        importedCount: appended.length,
        scheduleNames: appended.map((schedule) => schedule.name).toList(),
        icsWarnings: icsWarnings,
      ),
    );
  }
}

bool _matchesImportedGeneralScheduleId(
  String normalizedId,
  String requestedId,
) {
  final trimmed = requestedId.trim();
  return normalizedId == trimmed ||
      normalizedId == _sanitizeImportedGeneralId(trimmed);
}

GeneralScheduleData _normalizeGeneralScheduleData(GeneralScheduleData data) {
  final sourceSchedules = data.schedules.isEmpty
      ? const [
          GeneralSchedule(
            id: 'schedule_import',
            name: 'My calendar',
            events: [],
          ),
        ]
      : data.schedules;
  final requestedActiveScheduleId = data.activeScheduleId.trim();
  final scheduleIds = <String>{};
  final eventIds = <String>{};
  final occurrenceKeyRemaps = <_GeneralOccurrenceKeyRemap>[];
  final schedules = <GeneralSchedule>[];
  String? activeScheduleId;

  for (
    var scheduleIndex = 0;
    scheduleIndex < sourceSchedules.length;
    scheduleIndex++
  ) {
    final schedule = sourceSchedules[scheduleIndex];
    final rawScheduleId = schedule.id.trim();
    final scheduleId = _normalizeImportedGeneralId(
      rawScheduleId,
      fallbackPrefix: 'schedule_import',
      existingIds: scheduleIds,
    );
    scheduleIds.add(scheduleId);
    if (activeScheduleId == null &&
        _matchesGeneralActiveScheduleId(
          rawScheduleId: rawScheduleId,
          normalizedScheduleId: scheduleId,
          requestedActiveScheduleId: requestedActiveScheduleId,
        )) {
      activeScheduleId = scheduleId;
    }

    final events = <GeneralEvent>[];
    for (final event in schedule.events) {
      final rawEventId = event.id.trim();
      final eventId = _normalizeImportedGeneralId(
        rawEventId,
        fallbackPrefix: 'evt_import',
        existingIds: eventIds,
      );
      eventIds.add(eventId);
      final eventWithIds = event.copyWith(id: eventId, calendarId: scheduleId);
      final normalizedEventWithIds = eventWithIds.normalized(
        fallbackCalendarId: scheduleId,
      );
      occurrenceKeyRemaps.add(
        _GeneralOccurrenceKeyRemap(
          rawScheduleId: rawScheduleId,
          rawEventId: rawEventId,
          rawStartDateTimeIso: event.startDateTimeIso.trim(),
          scheduleId: scheduleId,
          eventId: eventId,
          startDateTimeIso: normalizedEventWithIds.startDateTimeIso,
        ),
      );
      events.add(normalizedEventWithIds);
    }

    schedules.add(
      schedule
          .copyWith(
            id: scheduleId,
            sortOrder: schedule.sortOrder < 0
                ? scheduleIndex
                : schedule.sortOrder,
            events: events,
          )
          .normalized(sortOrderFallback: scheduleIndex)
          .copyWith(sortOrder: schedules.length),
    );
  }

  final acknowledgements = <GeneralReminderAcknowledgement>[];
  for (final acknowledgement in data.reminderAcknowledgements) {
    final normalizedAcknowledgement = acknowledgement.normalized();
    if (normalizedAcknowledgement.occurrenceKey.isEmpty) {
      continue;
    }
    acknowledgements.add(
      GeneralReminderAcknowledgement(
        occurrenceKey: _remapGeneralOccurrenceKey(
          normalizedAcknowledgement.occurrenceKey,
          occurrenceKeyRemaps,
        ),
        isHandled: normalizedAcknowledgement.isHandled,
        updatedAtIso: normalizedAcknowledgement.updatedAtIso,
      ),
    );
  }

  return data.copyWith(
    activeScheduleId: activeScheduleId ?? schedules.first.id,
    schedules: schedules,
    reminderAcknowledgements: acknowledgements,
  );
}

bool _matchesGeneralActiveScheduleId({
  required String rawScheduleId,
  required String normalizedScheduleId,
  required String requestedActiveScheduleId,
}) {
  if (requestedActiveScheduleId.isEmpty) {
    return false;
  }
  return rawScheduleId == requestedActiveScheduleId ||
      normalizedScheduleId == requestedActiveScheduleId;
}

String _remapGeneralOccurrenceKey(
  String occurrenceKey,
  List<_GeneralOccurrenceKeyRemap> remaps,
) {
  final parsed = parseGeneralOccurrenceKey(occurrenceKey);
  if (parsed != null) {
    final remap = _selectGeneralOccurrenceKeyRemap(
      remaps,
      calendarId: parsed.calendarId,
      eventId: parsed.eventId,
      startDateTimeIso: parsed.startDateTimeIso,
    );
    if (remap != null) {
      if (remap.mapsToSameIds(
        calendarId: parsed.calendarId,
        eventId: parsed.eventId,
      )) {
        return occurrenceKey;
      }
      return buildGeneralOccurrenceKey(
        remap.scheduleId,
        remap.eventId,
        parsed.startDateTimeIso,
      );
    }
    return occurrenceKey;
  }
  final legacyCandidates = <_GeneralOccurrenceKeyRemap>[];
  String? legacyStartDateTimeIso;
  for (final remap in remaps) {
    final legacyPrefix = '${remap.rawScheduleId}|${remap.rawEventId}|';
    if (occurrenceKey.startsWith(legacyPrefix)) {
      legacyStartDateTimeIso = occurrenceKey.substring(legacyPrefix.length);
      legacyCandidates.add(remap);
    }
  }
  if (legacyStartDateTimeIso != null &&
      tryParseStrictIsoDateTime(legacyStartDateTimeIso) != null) {
    final remap = _selectGeneralOccurrenceKeyRemap(
      legacyCandidates,
      calendarId: legacyCandidates.first.rawScheduleId,
      eventId: legacyCandidates.first.rawEventId,
      startDateTimeIso: legacyStartDateTimeIso,
    );
    if (remap != null) {
      if (remap.mapsToSameIds(
        calendarId: remap.rawScheduleId,
        eventId: remap.rawEventId,
      )) {
        return occurrenceKey;
      }
      return buildGeneralOccurrenceKey(
        remap.scheduleId,
        remap.eventId,
        legacyStartDateTimeIso,
      );
    }
  }
  return occurrenceKey;
}

_GeneralOccurrenceKeyRemap? _selectGeneralOccurrenceKeyRemap(
  Iterable<_GeneralOccurrenceKeyRemap> remaps, {
  required String calendarId,
  required String eventId,
  required String startDateTimeIso,
}) {
  final candidates = remaps
      .where((remap) => remap.matchesIds(calendarId, eventId))
      .toList();
  if (candidates.length == 1) {
    return candidates.single;
  }
  final startCandidates = candidates
      .where((remap) => remap.matchesStart(startDateTimeIso))
      .toList();
  return startCandidates.length == 1 ? startCandidates.single : null;
}

class _GeneralOccurrenceKeyRemap {
  const _GeneralOccurrenceKeyRemap({
    required this.rawScheduleId,
    required this.rawEventId,
    required this.rawStartDateTimeIso,
    required this.scheduleId,
    required this.eventId,
    required this.startDateTimeIso,
  });

  final String rawScheduleId;
  final String rawEventId;
  final String rawStartDateTimeIso;
  final String scheduleId;
  final String eventId;
  final String startDateTimeIso;

  bool matchesIds(String calendarId, String eventId) {
    final matchesRaw = calendarId == rawScheduleId && eventId == rawEventId;
    final matchesNormalized =
        calendarId == scheduleId && eventId == this.eventId;
    return matchesRaw || matchesNormalized;
  }

  bool matchesStart(String startDateTimeIso) {
    return _sameOccurrenceStart(startDateTimeIso, rawStartDateTimeIso) ||
        _sameOccurrenceStart(startDateTimeIso, this.startDateTimeIso);
  }

  bool mapsToSameIds({required String calendarId, required String eventId}) {
    return scheduleId == calendarId && this.eventId == eventId;
  }
}

bool _sameOccurrenceStart(String left, String right) {
  if (left == right) {
    return true;
  }
  final leftParsed = tryParseStrictIsoDateTime(left);
  final rightParsed = tryParseStrictIsoDateTime(right);
  return leftParsed != null &&
      rightParsed != null &&
      leftParsed.isAtSameMomentAs(rightParsed);
}

Set<String> _generalEventIds(Iterable<GeneralSchedule> schedules) {
  return {
    for (final schedule in schedules)
      for (final event in schedule.events)
        if (event.id.trim().isNotEmpty) event.id.trim(),
  };
}

Set<String> _generalEventContentKeys(Iterable<GeneralSchedule> schedules) {
  return {
    for (final schedule in schedules)
      for (final event in schedule.events)
        _generalEventContentKey(schedule, event),
  };
}

List<GeneralEvent> _uniqueImportedGeneralEvents(
  GeneralSchedule schedule,
  Set<String> existingContentKeys,
) {
  final uniqueEvents = <GeneralEvent>[];
  for (final event in schedule.events) {
    final contentKey = _generalEventContentKey(schedule, event);
    if (!existingContentKeys.add(contentKey)) {
      continue;
    }
    uniqueEvents.add(event);
  }
  return uniqueEvents;
}

String _generalEventContentKey(GeneralSchedule schedule, GeneralEvent event) {
  final normalizedEvent = event.normalized(fallbackCalendarId: schedule.id);
  final reminderMinutes =
      normalizedEvent.reminders
          .map((reminder) => reminder.minutesBefore)
          .toList()
        ..sort();
  return jsonEncode({
    'calendarName': _normalizedGeneralText(schedule.name),
    'calendarColor': schedule.colorValue,
    'title': _normalizedGeneralText(normalizedEvent.title),
    'start': normalizedEvent.startDateTimeIso,
    'end': normalizedEvent.endDateTimeIso,
    'isAllDay': normalizedEvent.isAllDay,
    'recurrenceRule': normalizedEvent.recurrenceRule.toJson(),
    'recurrenceExceptionDates': normalizedEvent.recurrenceExceptionDateIso,
    'location': _normalizedGeneralText(normalizedEvent.location),
    'notes': _normalizedGeneralText(normalizedEvent.notes),
    'colorValue': normalizedEvent.colorValue,
    'reminders': reminderMinutes,
  });
}

String _normalizedGeneralText(String value) => value.trim();

String _normalizeImportedGeneralId(
  String rawId, {
  required String fallbackPrefix,
  required Set<String> existingIds,
}) {
  final sanitized = _sanitizeImportedGeneralId(rawId);
  final candidate = sanitized.isEmpty ? fallbackPrefix : sanitized;
  if (!existingIds.contains(candidate)) {
    return candidate;
  }
  final base = sanitized.isEmpty ? fallbackPrefix : _copyIdBase(sanitized);
  var next = base;
  var suffix = 1;
  while (existingIds.contains(next)) {
    next = '${base}_${suffix++}';
  }
  return next;
}

String _copyIdBase(String id) {
  final match = RegExp(r'^(.*_copy)(?:_\d+)?$').firstMatch(id);
  return match == null ? '${id}_copy' : match.group(1)!;
}

GeneralSchedule _sanitizeImportedGeneralSchedule(
  GeneralSchedule schedule, {
  required String scheduleId,
  required Set<String> existingEventIds,
}) {
  final events = <GeneralEvent>[];
  for (final event in schedule.events) {
    final eventId = _normalizeImportedGeneralId(
      event.id,
      fallbackPrefix: 'evt_import',
      existingIds: existingEventIds,
    );
    existingEventIds.add(eventId);
    events.add(event.copyWith(id: eventId, calendarId: scheduleId));
  }
  return schedule.copyWith(id: scheduleId, events: events);
}

String _sanitizeImportedGeneralId(String rawId) {
  return sanitizeImportedId(rawId);
}

bool _reminderKeyBelongsToSchedule(
  String occurrenceKey,
  GeneralSchedule schedule,
) {
  final parsed = parseGeneralOccurrenceKey(occurrenceKey);
  if (parsed != null) {
    return parsed.calendarId == schedule.id;
  }
  for (final event in schedule.events) {
    final prefix = '${schedule.id}|${event.id}|';
    if (occurrenceKey.startsWith(prefix) &&
        tryParseStrictIsoDateTime(occurrenceKey.substring(prefix.length)) !=
            null) {
      return true;
    }
  }
  final parts = occurrenceKey.split('|');
  return parts.length == 3 && parts.first == schedule.id;
}

String _generalIcsImportErrorMessage(
  GeneralCalendarIcsImportErrorCode code,
  String localeCode,
) {
  return switch (code) {
    GeneralCalendarIcsImportErrorCode.noEvents ||
    GeneralCalendarIcsImportErrorCode.noImportableEvents =>
      noSchedulesInImportMessage(localeCode: localeCode),
  };
}
