# 排课请求

请使用软件技能为这 {{course_count}} 节课进行排序,注意用户的要求设置。

## 课程清单

| courseId | 名称 | 时长(分钟) |
|---|---|---|
{{course_rows}}

## 用户要求设置

- **学习强度**:{{intensity_label}}(按 `intensity_matching_algorithm.json` 的 `{{intensity_key}}` 档执行)
- **排课窗口**:从{{start_label}}开始,共 {{days}} 天
- **每日可用时间窗**:{{window_description}}
- **每日固定休息段**:{{fixed_breaks}}(不可排课)
- **时间偏好**:{{time_preference}}
- **单次不可用时段**:{{one_off_blocks}}(不可排课)
- **备注**:{{notes}}

## 要求

请按 6 份技能文件执行:先评估每门课难度与重要程度 → 计算优先系数 → 生成可用时间片 → 按 `{{intensity_key}}` 档匹配 → 贪心分配(含碎片回收) → 自检验证 → 按 `output_format.json` 输出。
