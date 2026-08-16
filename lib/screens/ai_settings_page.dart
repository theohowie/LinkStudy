import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../courses/ai_scheduler.dart';
import '../widgets/sked_dropdown_menu.dart';

/// AI 排课设置页：提供商（DeepSeek/OpenAI）、Base URL、API Key（加密存储）、模型（下拉选择）、用量统计。
class AiScheduleSettingsPage extends StatefulWidget {
  const AiScheduleSettingsPage({super.key});

  @override
  State<AiScheduleSettingsPage> createState() => _AiScheduleSettingsPageState();
}

class _AiScheduleSettingsPageState extends State<AiScheduleSettingsPage> {
  final _settings = AiScheduleSettings();

  AiProvider _provider = AiProvider.deepseek;
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  String _model = '';
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;
  List<AiModelUsage> _usage = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadUsage();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadUsage() async {
    await AiUsageStats.instance.ensureLoaded();
    if (!mounted) return;
    setState(() => _usage = AiUsageStats.instance.entries);
  }

  Future<void> _openApiKeyPage(AiProvider provider) async {
    final uri = Uri.parse(
      provider == AiProvider.deepseek
          ? 'https://platform.deepseek.com/api_keys'
          : 'https://platform.openai.com/api-keys',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _load() async {
    final config = await _settings.loadConfig();
    if (!mounted) return;
    setState(() {
      _provider = config.provider;
      _baseUrlController.text = config.baseUrl;
      _apiKeyController.text = config.apiKey;
      // 存储的模型若不在当前提供商的可选项中，回退到默认模型。
      _model = _provider.modelOptions.contains(config.model)
          ? config.model
          : _provider.defaultModel;
      _loading = false;
    });
  }

  void _changeProvider(AiProvider provider) {
    if (provider == _provider) return;
    setState(() {
      _provider = provider;
      // 切换提供商时自动带默认 Base URL，模型切换为该提供商默认。
      if (_baseUrlController.text.trim().isEmpty ||
          _baseUrlController.text.trim() ==
              AiProvider.values
                  .firstWhere((p) => p != provider)
                  .defaultBaseUrl) {
        _baseUrlController.text = provider.defaultBaseUrl;
      }
      _model = provider.defaultModel;
    });
  }

  Future<void> _testConnection() async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final result = await AiScheduler().diagnoseConnection(
      _baseUrlController.text.trim().isEmpty
          ? _provider.defaultBaseUrl
          : _baseUrlController.text,
      apiKey: _apiKeyController.text,
    );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _settings.saveConfig(
        provider: _provider,
        baseUrl: _baseUrlController.text,
        model: _model,
        apiKey: _apiKeyController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('AI 排课设置已保存')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 排课设置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  '提供商',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                SegmentedButton<AiProvider>(
                  segments: [
                    ButtonSegment(
                      value: AiProvider.deepseek,
                      icon: SvgPicture.asset(
                        'assets/icons/deepseek.svg',
                        width: 18,
                        height: 18,
                        colorFilter: ColorFilter.mode(
                          Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black,
                          BlendMode.srcIn,
                        ),
                      ),
                      label: const Text('DeepSeek'),
                    ),
                    ButtonSegment(
                      value: AiProvider.openai,
                      icon: SvgPicture.asset(
                        'assets/icons/openai.svg',
                        width: 18,
                        height: 18,
                        colorFilter: ColorFilter.mode(
                          Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black,
                          BlendMode.srcIn,
                        ),
                      ),
                      label: const Text('OpenAI'),
                    ),
                  ],
                  selected: {_provider},
                  onSelectionChanged: (selection) =>
                      _changeProvider(selection.first),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Base URL',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _baseUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    hintText: 'https://api.deepseek.com/v1',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'API Key',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _apiKeyController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: 'sk-…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '模型',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                SkedDropdownMenu<String>(
                  initialSelection: _model,
                  label: const Text('选择模型'),
                  leadingIcon: const Icon(Icons.memory_outlined),
                  expandedInsets: EdgeInsets.zero,
                  dropdownMenuEntries: [
                    for (final model in _provider.modelOptions)
                      DropdownMenuEntry(value: model, label: model),
                  ],
                  onSelected: (value) {
                    if (value != null) {
                      setState(() => _model = value);
                    }
                  },
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _testing ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check_outlined),
                  label: const Text('测试网络连接'),
                ),
                if (_testResult != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _testResult!,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: _testResult!.contains('超时') ||
                              _testResult!.contains('失败')
                          ? Theme.of(context).colorScheme.error
                          : Colors.green,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'API Key 加密存储在系统安全存储中；Base URL 与模型保存在本机。'
                  '仅当你主动发起 AI 排课时，课程信息才会发送到你配置的接口。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                // 用量统计（分模型）。
                const Text(
                  '用量统计',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _usage.isEmpty
                      ? const Text(
                          '暂无用量数据，开始 AI 排课后自动统计',
                          style: TextStyle(fontSize: 13),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final u in _usage)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        u.model,
                                        style: const TextStyle(fontSize: 13),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${u.requests} 次 · ${u.totalTokens} tokens · '
                                      '约 \$ ${estimateCostInUsd(u).toStringAsFixed(4)}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            const Divider(height: 12),
                            Text(
                              '总计：${AiUsageStats.instance.totalRequests} 次 · '
                              '${AiUsageStats.instance.totalTokens} tokens · '
                              '约 \$ ${AiUsageStats.instance.totalCostUsd.toStringAsFixed(4)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '费用为按模型公开定价估算，实际以平台账单为准。',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                // 创建 API Key 快捷跳转。
                OutlinedButton.icon(
                  onPressed: () => _openApiKeyPage(_provider),
                  icon: const Icon(Icons.vpn_key_outlined),
                  label: Text(
                    _provider == AiProvider.deepseek
                        ? '去 DeepSeek 创建 API Key'
                        : '去 OpenAI 创建 API Key',
                  ),
                ),
              ],
            ),
    );
  }
}
