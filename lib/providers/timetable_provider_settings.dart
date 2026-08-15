part of 'timetable_provider.dart';

mixin _TimetableProviderSettings on _TimetableProviderBase {
  Future<void> updateLocaleCode(String localeCode) async {
    _appData = _settings.updateLocaleCode(_appData, localeCode);
    await _saveAndNotify();
  }

  Future<void> updateThemeMode(String themeMode) async {
    _appData = _settings.updateThemeMode(_appData, themeMode);
    await _saveAndNotify();
  }

  Future<void> updateThemeSeedColorValue(int colorValue) async {
    _appData = _settings.updateThemeSeedColorValue(_appData, colorValue);
    await _saveAndNotify();
  }

  Future<void> updateThemeColorMode(String mode) async {
    _appData = _settings.updateThemeColorMode(_appData, mode);
    await _saveAndNotify();
  }

  Future<void> updateColorfulUiColorValue(String key, int colorValue) async {
    _appData = _settings.updateColorfulUiColorValue(_appData, key, colorValue);
    await _saveAndNotify();
  }
}
