import 'package:flutter/services.dart' show rootBundle;

/// AI 排课技能文件包：提示词 md + 算法 JSON，程序从 assets 加载后随请求发给 AI。
///
/// 结构（与 assets 目录对应）：
/// - [systemPrompt]：`assets/prompts/system_prompt.md`，引导 AI 读取技能文件并执行；
/// - [userTemplate]：`assets/prompts/user_prompt.md`，排课请求模板（`{{占位符}}` 由程序填充）；
/// - [schemeFiles]：`assets/schemes/*.json`，算法方案（AHP 优先系数 / 时间片 / 强度匹配 / 贪心分配 / 输出格式）。
class AiSkillPackage {
  const AiSkillPackage({
    required this.systemPrompt,
    required this.userTemplate,
    required this.schemeFiles,
  });

  final String systemPrompt;
  final String userTemplate;
  final Map<String, String> schemeFiles;
}

/// 从 App 资源加载 [AiSkillPackage]；任一文件缺失/加载失败返回 null，
/// 由调用方降级为内置精简 prompt（保证功能不中断）。
class AiSkillPackageLoader {
  const AiSkillPackageLoader();

  static const _systemPath = 'assets/prompts/system_prompt.md';
  static const _userPath = 'assets/prompts/user_prompt.md';
  static const _schemePaths = [
    'assets/schemes/ahp_priority_algorithm.json',
    'assets/schemes/time_slices_algorithm.json',
    'assets/schemes/intensity_matching_algorithm.json',
    'assets/schemes/greedy_allocation_algorithm.json',
    'assets/schemes/output_format.json',
  ];

  Future<AiSkillPackage?> load() async {
    try {
      final system = await rootBundle.loadString(_systemPath);
      final user = await rootBundle.loadString(_userPath);
      final schemes = <String, String>{};
      for (final path in _schemePaths) {
        final name = path.split('/').last;
        schemes[name] = await rootBundle.loadString(path);
      }
      return AiSkillPackage(
        systemPrompt: system,
        userTemplate: user,
        schemeFiles: schemes,
      );
    } catch (e) {
      // 技能文件缺失（如测试环境或资源未打包）→ 返回 null，调用方回退内置 prompt。
      return null;
    }
  }
}
