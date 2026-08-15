import '../models/general_models.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_locale.dart' as app_locale;
import '../l10n/app_localizations.dart';
import '../providers/timetable_provider.dart';
import '../utils/time_utils.dart';
import '../widgets/sked_dropdown_menu.dart';
import '../widgets/settings_list.dart';

class GeneralDisplaySettingsPage extends StatelessWidget {
  const GeneralDisplaySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Consumer<TimetableProvider>(
      builder: (context, provider, child) {
        final localeCode = app_locale.normalizeLocaleCode(provider.localeCode);
        return Scaffold(
          appBar: AppBar(title: Text(l10n.generalDisplaySettings)),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              SettingsSectionHeader(title: l10n.generalDefaultViewSection),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SkedDropdownMenu<String>(
                  initialSelection: provider.generalDefaultView,
                  label: Text(l10n.defaultView),
                  leadingIcon: const Icon(Icons.space_dashboard_outlined),
                  expandedInsets: EdgeInsets.zero,
                  dropdownMenuEntries: [
                    DropdownMenuEntry(
                      value: generalViewWeek,
                      label: l10n.viewWeek,
                    ),
                    DropdownMenuEntry(
                      value: generalViewDay,
                      label: l10n.viewDay,
                    ),
                    DropdownMenuEntry(
                      value: generalViewList,
                      label: l10n.viewList,
                    ),
                    DropdownMenuEntry(
                      value: generalViewMonth,
                      label: l10n.viewMonth,
                    ),
                  ],
                  onSelected: (value) {
                    if (value != null) {
                      provider.updateGeneralDisplaySettings(defaultView: value);
                    }
                  },
                ),
              ),
              SettingsSectionHeader(title: l10n.generalScheduleDisplaySection),
              SettingsSwitchTile(
                icon: Icons.weekend_outlined,
                title: l10n.showWeekends,
                value: provider.generalShowWeekends,
                onChanged: (value) =>
                    provider.updateGeneralDisplaySettings(showWeekends: value),
              ),
              if (localeCode == 'zh' || localeCode == 'zh-Hant')
                SettingsSwitchTile(
                  icon: Icons.brightness_2_outlined,
                  title: l10n.showLunarCalendar,
                  value: provider.generalShowLunarCalendar,
                  onChanged: (value) => provider.updateGeneralDisplaySettings(
                    showLunarCalendar: value,
                  ),
                ),
              SettingsSectionHeader(title: l10n.generalTimeGridSection),
              _TimeSettingTile(
                icon: Icons.access_time,
                title: l10n.startHour,
                minute: provider.generalDayStartMinute,
                onTap: () => _pickTime(
                  context,
                  provider,
                  initialMinute: provider.generalDayStartMinute,
                  onPicked: (minute) =>
                      provider.updateGeneralDisplaySettings(
                        dayStartMinute: minute,
                      ),
                ),
              ),
              _TimeSettingTile(
                icon: Icons.access_time,
                title: l10n.endHour,
                minute: provider.generalDayEndMinute,
                onTap: () => _pickTime(
                  context,
                  provider,
                  initialMinute: provider.generalDayEndMinute,
                  onPicked: (minute) =>
                      provider.updateGeneralDisplaySettings(
                        dayEndMinute: minute,
                      ),
                ),
              ),
              _TimeSettingTile(
                icon: Icons.free_breakfast_outlined,
                title: l10n.lunchStartHour,
                minute: provider.generalLunchStartMinute,
                onTap: () => _pickTime(
                  context,
                  provider,
                  initialMinute: provider.generalLunchStartMinute,
                  onPicked: (minute) =>
                      provider.updateGeneralDisplaySettings(
                        lunchStartMinute: minute,
                      ),
                ),
              ),
              _TimeSettingTile(
                icon: Icons.free_breakfast_outlined,
                title: l10n.lunchEndHour,
                minute: provider.generalLunchEndMinute,
                onTap: () => _pickTime(
                  context,
                  provider,
                  initialMinute: provider.generalLunchEndMinute,
                  onPicked: (minute) =>
                      provider.updateGeneralDisplaySettings(
                        lunchEndMinute: minute,
                      ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SkedDropdownMenu<int>(
                  initialSelection: provider.generalTimeGridMinutes,
                  label: Text(l10n.timeGridDensity),
                  leadingIcon: const Icon(Icons.grid_4x4_outlined),
                  expandedInsets: EdgeInsets.zero,
                  dropdownMenuEntries: [
                    DropdownMenuEntry(
                      value: 15,
                      label: l10n.timeGridMinutes(15),
                    ),
                    DropdownMenuEntry(
                      value: 30,
                      label: l10n.timeGridMinutes(30),
                    ),
                    DropdownMenuEntry(
                      value: 60,
                      label: l10n.timeGridMinutes(60),
                    ),
                  ],
                  onSelected: (value) {
                    if (value != null) {
                      provider.updateGeneralDisplaySettings(
                        timeGridMinutes: value,
                      );
                    }
                  },
                ),
              ),
              SettingsSectionHeader(title: l10n.generalPopupSection),
              SettingsSwitchTile(
                icon: Icons.open_in_full_outlined,
                title: l10n.closePopupOnOutsideTap,
                value: provider.closeGeneralEventPopupOnOutsideTap,
                onChanged: (value) => provider.updateGeneralDisplaySettings(
                  closeEventPopupOnOutsideTap: value,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 时间设置项：显示当前时间（HH:mm），点击弹出时间选择器（精确到分钟）。
class _TimeSettingTile extends StatelessWidget {
  const _TimeSettingTile({
    required this.icon,
    required this.title,
    required this.minute,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final int minute;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SettingsListTile(
      leading: Icon(icon),
      title: title,
      subtitle: formatMinutes(minute),
      trailing: const Icon(Icons.access_time),
      onTap: onTap,
    );
  }
}

/// 弹出时间选择器，选择结果以分钟回调。
Future<void> _pickTime(
  BuildContext context,
  TimetableProvider provider, {
  required int initialMinute,
  required ValueChanged<int> onPicked,
}) async {
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(
      hour: initialMinute ~/ 60,
      minute: initialMinute % 60,
    ),
    helpText: '选择时间',
    cancelText: '取消',
    confirmText: '确定',
  );
  if (picked == null) return;
  onPicked(picked.hour * 60 + picked.minute);
}
