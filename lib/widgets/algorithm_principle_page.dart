import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 算法原理页：软件内渲染 HTML 介绍 AI 排课四个算法（不跳外部链接）。
class AlgorithmPrinciplePage extends StatefulWidget {
  const AlgorithmPrinciplePage({super.key});

  @override
  State<AlgorithmPrinciplePage> createState() => _AlgorithmPrinciplePageState();
}

class _AlgorithmPrinciplePageState extends State<AlgorithmPrinciplePage> {
  String? _html;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final html = await rootBundle.loadString(
        'assets/algorithm_principles.html',
      );
      if (mounted) setState(() => _html = html);
    } catch (e) {
      if (mounted) setState(() => _error = '加载失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 排课原理')),
      body: _error != null
          ? Center(child: Text(_error!))
          : _html == null
          ? const Center(child: CircularProgressIndicator())
          : InAppWebView(
              initialData: InAppWebViewInitialData(
                data: _html!,
                baseUrl: WebUri('https://local/assets'),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                verticalScrollBarEnabled: true,
                transparentBackground: false,
              ),
            ),
    );
  }
}
