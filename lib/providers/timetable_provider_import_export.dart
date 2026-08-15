part of 'timetable_provider.dart';

mixin _TimetableProviderImportExport on _TimetableProviderBase {
  String exportSelectedGeneralSchedulesJson(List<String> scheduleIds) {
    return _importExportService.exportSelectedGeneralSchedulesJson(
      _appData.generalMode,
      scheduleIds,
      localeCode: _appData.localeCode,
    );
  }

  String exportActiveGeneralScheduleJson() {
    final active = activeGeneralScheduleOrNull;
    if (active == null) {
      throw FormatException(
        noExportableScheduleMessage(localeCode: _appData.localeCode),
      );
    }
    return exportSelectedGeneralSchedulesJson([active.id]);
  }

  String exportSelectedGeneralSchedulesIcs(List<String> scheduleIds) {
    return _importExportService.exportSelectedGeneralSchedulesIcs(
      _appData.generalMode,
      scheduleIds,
      localeCode: _appData.localeCode,
    );
  }

  GeneralCalendarIcsImportResult previewImportGeneralSchedulesIcs(
    String source,
  ) {
    return _importExportService.previewImportGeneralSchedulesIcs(
      source,
      localeCode: _appData.localeCode,
    );
  }

  List<GeneralSchedule> previewImportGeneralSchedules(String source) {
    return _importExportService.previewImportGeneralSchedules(
      source,
      localeCode: _appData.localeCode,
    );
  }

  Future<GeneralScheduleImportResult> importSelectedGeneralSchedulesJson(
    String source, {
    required List<String> scheduleIds,
    required GeneralScheduleImportMode mode,
  }) async {
    final mutation = _importExportService.importSelectedGeneralSchedulesJson(
      _appData.generalMode,
      source,
      scheduleIds: scheduleIds,
      mode: mode,
      localeCode: _appData.localeCode,
    );
    _appData = _appData.copyWith(generalMode: mutation.data);
    await _saveAndNotify();
    return mutation.result;
  }

  Future<GeneralScheduleImportResult> importGeneralSchedulesIcs(
    String source, {
    required GeneralScheduleImportMode mode,
  }) async {
    final mutation = _importExportService.importGeneralSchedulesIcs(
      _appData.generalMode,
      source,
      mode: mode,
      localeCode: _appData.localeCode,
    );
    _appData = _appData.copyWith(generalMode: mutation.data);
    await _saveAndNotify();
    return mutation.result;
  }

  String exportAppDataJson() =>
      _importExportService.exportAppDataJson(_appData);

  Future<int> importAppDataJson(
    String source, {
    required AppImportMode mode,
  }) async {
    final imported = _importExportService.normalizeAppData(
      decodeAppDataEnvelope(source, localeCode: _appData.localeCode),
      localeCode: _appData.localeCode,
    );
    if (mode == AppImportMode.replaceAll) {
      _appData = imported;
      await _saveAndNotify();
      return imported.generalMode.schedules.length;
    }

    final mutation = _importExportService.importSelectedGeneralSchedulesJson(
      _appData.generalMode,
      source,
      scheduleIds: imported.generalMode.schedules
          .map((item) => item.id)
          .toList(),
      mode: GeneralScheduleImportMode.addAsNew,
      localeCode: _appData.localeCode,
    );
    _appData = _appData.copyWith(generalMode: mutation.data);
    await _saveAndNotify();
    return mutation.result.importedCount;
  }

  @override
  Future<AppData> _buildDefaultAppData() async {
    final localeCode = _systemLocaleCodeResolver();
    return _importExportService.normalizeAppData(
      buildInitialAppData(localeCode: localeCode),
      localeCode: localeCode,
    );
  }
}
