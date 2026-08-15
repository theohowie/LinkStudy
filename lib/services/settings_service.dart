import '../l10n/app_locale.dart';
import '../models/app_data.dart';
import '../utils/time_utils.dart';

class SettingsService {
  const SettingsService();

  AppData updateLocaleCode(AppData data, String localeCode) {
    if (data.localeCode == localeCode) return data;
    return data.copyWith(localeCode: normalizeLocaleCode(localeCode));
  }

  AppData updateThemeMode(AppData data, String themeMode) {
    final normalized = normalizeThemeMode(themeMode);
    if (data.generalMode.themeMode == normalized) return data;
    return data.copyWith(
      generalMode: data.generalMode.copyWith(themeMode: normalized),
    );
  }

  AppData updateThemeColorMode(AppData data, String mode) {
    final normalized = normalizeThemeColorMode(mode);
    if (data.generalMode.themeColorMode == normalized) return data;
    return data.copyWith(
      generalMode: data.generalMode.copyWith(themeColorMode: normalized),
    );
  }

  AppData updateThemeSeedColorValue(AppData data, int colorValue) {
    if (data.generalMode.themeSeedColorValue == colorValue) return data;
    return data.copyWith(
      generalMode: data.generalMode.copyWith(themeSeedColorValue: colorValue),
    );
  }

  AppData updateColorfulUiColorValue(AppData data, String key, int colorValue) {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) return data;
    if (data.generalMode.colorfulUiColorValues[normalizedKey] == colorValue) {
      return data;
    }
    final updated = Map<String, int>.from(
      data.generalMode.colorfulUiColorValues,
    )..[normalizedKey] = colorValue;
    return data.copyWith(
      generalMode: data.generalMode.copyWith(colorfulUiColorValues: updated),
    );
  }

  AppData ignoreUpdateVersion(AppData data, String version) {
    final normalized = version.trim();
    if (normalized.isEmpty || data.ignoredUpdateVersion == normalized) {
      return data;
    }
    return data.copyWith(ignoredUpdateVersion: normalized);
  }

  AppData updateAvailableUpdateVersion(AppData data, String? version) {
    final normalized = version?.trim();
    final nextValue = normalized == null || normalized.isEmpty
        ? null
        : normalized;
    if (data.availableUpdateVersion == nextValue) return data;
    return data.copyWith(availableUpdateVersion: nextValue);
  }
}
