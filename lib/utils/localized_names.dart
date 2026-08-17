import '../l10n/app_locale.dart';
import '../l10n/app_localizations.dart';

AppLocalizations _l10nForLocale(String localeCode) {
  return lookupAppLocalizations(appLocaleFromCode(localeCode));
}

String defaultPeriodTimeSetName({String localeCode = defaultLocaleCode}) {
  return _l10nForLocale(localeCode).defaultPeriodTimeSetName;
}

String periodTimeSetFallbackName({String localeCode = defaultLocaleCode}) {
  return _l10nForLocale(localeCode).periodTimeSetFallbackName;
}

String untitledTimetableName({String localeCode = defaultLocaleCode}) {
  return _l10nForLocale(localeCode).untitledTimetableName;
}

String newTimetableName({String localeCode = defaultLocaleCode}) {
  return _l10nForLocale(localeCode).newTimetableName;
}

String newPeriodTimeSetName({String localeCode = defaultLocaleCode}) {
  return _l10nForLocale(localeCode).newPeriodTimeSetName;
}

String emptyTimetableName({String localeCode = defaultLocaleCode}) {
  return _l10nForLocale(localeCode).emptyTimetableName;
}

String importedPeriodTimeSetName(
  String timetableName, {
  String localeCode = defaultLocaleCode,
}) {
  return _l10nForLocale(localeCode).importedPeriodTimeSetName(timetableName);
}

String importFileTypeMismatchMessage({String localeCode = defaultLocaleCode}) {
  return _l10nForLocale(localeCode).importFileTypeMismatchMessage;
}

String importFileVersionUnsupportedMessage({
  String localeCode = defaultLocaleCode,
}) {
  return _l10nForLocale(localeCode).importFileVersionUnsupportedMessage;
}

String noPeriodTimesInImportMessage({String localeCode = defaultLocaleCode}) {
  return _l10nForLocale(localeCode).noPeriodTimesInImportMessage;
}

String noPeriodTimeAvailableMessage({String localeCode = defaultLocaleCode}) {
  return _l10nForLocale(localeCode).noPeriodTimeAvailable;
}

String noImportableTimetablesMessage({String localeCode = defaultLocaleCode}) {
  return _l10nForLocale(localeCode).noImportableTimetables;
}

String selectAtLeastOneTimetableMessage({
  String localeCode = defaultLocaleCode,
}) {
  return _l10nForLocale(localeCode).selectAtLeastOneTimetableMessage;
}

String noExportableTimetableMessage({String localeCode = defaultLocaleCode}) {
  return _l10nForLocale(localeCode).noExportableTimetableMessage;
}

String replaceActiveRequiresSingleTimetableMessage({
  String localeCode = defaultLocaleCode,
}) {
  return _l10nForLocale(
    localeCode,
  ).replaceActiveRequiresSingleTimetableMessage;
}

String noActiveTimetableToReplaceMessage({
  String localeCode = defaultLocaleCode,
}) {
  return _l10nForLocale(localeCode).noActiveTimetableToReplaceMessage;
}

String periodTimeSetInUseMessage(
  int count, {
  String localeCode = defaultLocaleCode,
}) {
  return _l10nForLocale(localeCode).periodTimeSetInUseMessage(count);
}

String selectAtLeastOneScheduleMessage({
  String localeCode = defaultLocaleCode,
}) {
  return _l10nForLocale(localeCode).selectAtLeastOneScheduleMessage;
}

String noExportableScheduleMessage({String localeCode = defaultLocaleCode}) {
  return _l10nForLocale(localeCode).noExportableScheduleMessage;
}

String noSchedulesInImportMessage({String localeCode = defaultLocaleCode}) {
  return _l10nForLocale(localeCode).noSchedulesInImportMessage;
}

String replaceActiveRequiresSingleScheduleMessage({
  String localeCode = defaultLocaleCode,
}) {
  return _l10nForLocale(
    localeCode,
  ).replaceActiveRequiresSingleScheduleMessage;
}

String noActiveScheduleToReplaceMessage({
  String localeCode = defaultLocaleCode,
}) {
  return _l10nForLocale(localeCode).noActiveScheduleToReplaceMessage;
}
