import 'package:flutter_test/flutter_test.dart';
import 'package:linkstudy/courses/ai_skill_package.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('技能文件包从 assets 加载成功（真实资源）', () async {
    final pkg = await const AiSkillPackageLoader().load();
    expect(pkg, isNotNull);
    expect(pkg!.systemPrompt, contains('学习排课规划助手'));
    expect(pkg.userTemplate, contains('{{course_rows}}'));
    // 5 份算法 JSON 全部加载。
    expect(pkg.schemeFiles.keys, {
      'ahp_priority_algorithm.json',
      'time_slices_algorithm.json',
      'intensity_matching_algorithm.json',
      'greedy_allocation_algorithm.json',
      'output_format.json',
    });
    expect(pkg.schemeFiles['ahp_priority_algorithm.json'], contains('AHP'));
    expect(pkg.schemeFiles['output_format.json'], contains('startTime'));
  });

  test('技能文件包缺失时返回 null（降级）', () async {
    expect(await const _BrokenLoader().load(), isNull);
  });
}

class _BrokenLoader extends AiSkillPackageLoader {
  const _BrokenLoader();

  @override
  Future<AiSkillPackage?> load() async => null;
}
