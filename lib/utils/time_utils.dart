import 'package:flutter/material.dart';

import 'constants.dart';

int normalizeMinuteOfDay(int? minutes, {int fallback = 0}) {
  return (minutes ?? fallback).clamp(0, (24 * 60) - 1).toInt();
}

String formatMinutes(int minutes) {
  final normalized = normalizeMinuteOfDay(minutes);
  final hour = (normalized ~/ 60).toString().padLeft(2, '0');
  final minute = (normalized % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}

DateTime normalizeDateOnly(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

DateTime? tryParseStrictIsoDateTime(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?)?(Z|[+-]\d{2}:?\d{2})?$',
  ).firstMatch(trimmed);
  if (match == null) {
    return null;
  }

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4) ?? '0');
  final minute = int.parse(match.group(5) ?? '0');
  final second = int.parse(match.group(6) ?? '0');
  if (!_isValidDateTimeParts(
    year: year,
    month: month,
    day: day,
    hour: hour,
    minute: minute,
    second: second,
  )) {
    return null;
  }
  return DateTime.tryParse(trimmed);
}

DateTime? tryParseStrictIsoDate(String? value) {
  final parsed = tryParseStrictIsoDateTime(value);
  return parsed == null ? null : normalizeDateOnly(parsed);
}

bool _isValidDateTimeParts({
  required int year,
  required int month,
  required int day,
  required int hour,
  required int minute,
  required int second,
}) {
  if (year < 1 ||
      year > 9999 ||
      month < 1 ||
      month > 12 ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59 ||
      second < 0 ||
      second > 59) {
    return false;
  }
  return day >= 1 && day <= DateTime(year, month + 1, 0).day;
}

DateTime startOfWeekMonday(DateTime date) {
  final normalized = normalizeDateOnly(date);
  return normalized.subtract(
    Duration(days: normalized.weekday - DateTime.monday),
  );
}

DateTime startOfWeekSunday(DateTime date) {
  final normalized = normalizeDateOnly(date);
  return normalized.subtract(Duration(days: normalized.weekday % 7));
}

String normalizeThemeMode(String? themeMode) {
  switch (themeMode) {
    case 'dark':
      return 'dark';
    case 'system':
      return 'system';
    case 'light':
      return 'light';
    default:
      return defaultThemeMode;
  }
}

String normalizeThemeColorMode(String? themeColorMode) {
  switch (themeColorMode) {
    case themeColorModeColorful:
      return themeColorModeColorful;
    case themeColorModeSingle:
    default:
      return themeColorModeSingle;
  }
}

Map<String, int> decodeColorValueMap(dynamic value) {
  if (value is! Map) {
    return const {};
  }
  final result = <String, int>{};
  value.forEach((key, item) {
    final normalizedKey = '$key'.trim();
    final colorValue = item is num ? item.toInt() : null;
    if (normalizedKey.isEmpty || colorValue == null) {
      return;
    }
    result[normalizedKey] = colorValue;
  });
  return result;
}
