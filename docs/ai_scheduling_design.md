# LinkStudy AI 智能排课设计（2026-08-15）

> 状态：已与用户确认（2026-08-15 会话）｜回滚点：git `6e407ab`（已推送 GitHub）

## 定位

**AI = 排课决策引擎，软件 = 流程编排器。** 软件把用户需求整理成高精度 Prompt（内置"排课 Skill"为 system，结构化数据为 user），AI 按 Skill 输出固定格式 JSON，软件解析后本地落位并同步到网格。

## 流程

采集入池 → 勾选课程（半弹窗卡片）→ 本次设置（强度/天数/备注/时间偏好）→ 组装 Prompt → AI 排课 → 解析 → 本地引擎落位（校验+休息）→ 网格同步 → SnackBar 汇报。

## 数据分层

- **固定设置**：通用显示设置里 开始/午休/结束 时间窗（学习可用时段）；AI 提供商/BaseURL/Key/模型。
- **本次设置**：强度（轻松🍃/中等⚖️/压力🔥，诙谐文案）、计划天数（1-14）、备注（已有安排约束）、时间偏好（可空=全天）。**记住上次选择**（SharedPreferences 预填）。

## 组件

| 组件 | 文件 | 说明 |
|---|---|---|
| 午休模型 | `general_schedule_data.dart` 等 | `lunchStartHour`(默认12)/`lunchEndHour`(默认13)，贯穿 toJson/fromJson/copyWith/normalized/updateDisplaySettings/显示设置 UI；旧数据默认值兼容 |
| 入池 | `link_course.dart` | `addCourse` 不再自动排课；`pendingCount`；`scheduleWithOrder(order, days, availability)` 落位+网格同步 |
| 引擎 | `scheduler_engine.dart` | `scheduleCourses` 增可选 `ordered`（courseId+restAfterMinutes）与 `horizonDays`（默认 7→计划天数）；休息作为课后占用，放不下则忽略休息保课程落位 |
| AI 服务 | `courses/ai_scheduler.dart` 新 | OpenAI 兼容 `{baseUrl}/chat/completions`，15s 超时；内置排课 Skill system prompt；输出 `{"order":[{"courseId","restAfterMinutes"}],"reason"}`；解析容错；类型化错误（未配置/网络/HTTP/JSON） |
| 密钥 | `secret_store.dart` 扩展 | `aiSchedulerApiKey` 槽位（flutter_secure_storage） |
| AI 配置 | SharedPreferences | 提供商（deepseek/openai）、BaseURL（默认 `https://api.deepseek.com/v1` / `https://api.openai.com/v1`）、模型（`deepseek-chat`/`gpt-4o-mini`） |
| 池弹窗 | `widgets/course_pending_sheet.dart` 新 | 卡片：圆形勾选框（左，垂直居中）｜上行 课程名(左)+时长(右)；下行 链接；全选/删除（带确认）；"下一步"门禁（≥1） |
| 设置弹窗 | `widgets/ai_schedule_setup_sheet.dart` 新 | 强度/天数/备注/时间偏好 + 预填上次 + "开始 AI 排课" |
| 首页入口 | `general_schedule_home_screen.dart` | AppBar actions 最左（日历按钮左边）排课按钮 + 未排课数量角标 |
| 设置页 | `settings_page.dart` | 新增"AI 排课"分组 |

## 失败处理

AI 失败（未配置/网络/HTTP/解析）→ SnackBar 气泡显示错误；自动回退贪心顺序落位（流程不中断）。

## 时间窗映射

学习可用时段（分钟级）＝ `[开始*60, 午休开始*60) + [午休结束*60, 结束*60)`；午休无效时退化为 `[开始*60, 结束*60)`。AI 请求中同时携带（AI 参考），本地落位强制执行。

## 测试

`ai_scheduler_test`（prompt/解析/错误/超时，mock http）、`scheduler_engine_test`（ordered/休息/天数）、`link_course_test`（入池/顺序落位/回退）、widget（角标/勾选/全选/删除/门禁）。
