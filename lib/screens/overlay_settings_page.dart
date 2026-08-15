import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/overlay_client.dart';

/// 悬浮窗样式设置页：悬浮球样式（黑胶囊 / 白圆球）与透明度。
/// 选择即时生效（悬浮窗开启时实时应用），并持久化到 SharedPreferences。
class OverlaySettingsPage extends StatefulWidget {
  const OverlaySettingsPage({super.key});

  @override
  State<OverlaySettingsPage> createState() => _OverlaySettingsPageState();
}

class _OverlaySettingsPageState extends State<OverlaySettingsPage> {
  String _style = overlayStyleCapsuleBlack;
  int _opacity = 100;
  bool _overlayRunning = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final client = OverlayClient();
      final granted = await client.isPermissionGranted();
      if (!mounted) return;
      setState(() {
        _style = prefs.getString(overlayPrefsStyleKey) ?? overlayStyleCapsuleBlack;
        _opacity = prefs.getInt(overlayPrefsOpacityKey) ?? 100;
        _overlayRunning = granted &&
            (prefs.getBool(overlayPrefsEnabledKey) ?? false);
      });
    } catch (_) {
      // 平台通道不可用时保持默认值
    }
  }

  Future<void> _changeStyle(String style) async {
    if (style == _style) return;
    setState(() => _style = style);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(overlayPrefsStyleKey, style);
    if (_overlayRunning) {
      try {
        await OverlayClient().setOverlayStyle(style);
      } catch (_) {}
    }
  }

  Future<void> _changeOpacity(int opacity) async {
    setState(() => _opacity = opacity);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(overlayPrefsOpacityKey, opacity);
    if (_overlayRunning) {
      try {
        await OverlayClient().setOverlayOpacity(opacity);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('悬浮球样式')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '悬浮球样式',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _StyleOptionCard(
                  label: '黑色胶囊',
                  preview: Container(
                    width: 72,
                    height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  selected: _style == overlayStyleCapsuleBlack,
                  onTap: () => _changeStyle(overlayStyleCapsuleBlack),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StyleOptionCard(
                  label: '白色圆球',
                  preview: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFC8C8C8)),
                    ),
                  ),
                  selected: _style == overlayStyleBallWhite,
                  onTap: () => _changeStyle(overlayStyleBallWhite),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '透明度',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              Text('$_opacity%'),
            ],
          ),
          Slider(
            value: _opacity.toDouble(),
            min: 20,
            max: 100,
            divisions: 16,
            label: '$_opacity%',
            onChanged: (v) => _changeOpacity(v.toInt()),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '使用说明',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  '· 拖动悬浮球可移动位置\n'
                  '· 点击悬浮球弹出填写面板（链接/名称/时长），不跳转前台\n'
                  '· 复制链接后点面板"粘贴链接"自动填入',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StyleOptionCard extends StatelessWidget {
  const _StyleOptionCard({
    required this.label,
    required this.preview,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Widget preview;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colors.primary.withValues(alpha: 0.08)
          : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            children: [
              preview,
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label),
                  if (selected) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.check_circle, size: 16, color: colors.primary),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
