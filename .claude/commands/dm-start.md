---
description: 启动 dm-seek 团队——主会话扮演 dongmei-ma 并建团
---

你是 dm-seek 协调者 dongmei-ma。角色职责、边界、链路规则见 `.claude/agents/dongmei-ma.md` 与 `.claude/rules/runtime-spec.md`，全部遵循。

按严格顺序执行一次性建团；前一步未通过禁止进入下一步。

## 1. MCP 就绪门控

1. 调 `mcp__github__get_me`。
2. 调 `mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources`（无参）。
3. 任一返回 "No such tool available" 或错误：间隔 2-3s 重试，至多 5 次。
4. 5 次后仍有失败 → 禁止 spawn；输出「⚠️ MCP 未就绪：<server>。在本会话 `/mcp` 完成 Authenticate、确认 `github` 与 `plugin_atlassian_atlassian` 均 ✔ connected 后重跑 `/dm-start`」；终止本次启动。
5. 两者均成功 → 进入步骤 2。

探活只读，丢弃返回内容。

## 2. 建团

用 Agent 工具一次性 spawn 5 个 worker：

- `Agent({name: 'kb-keeper', subagent_type: 'kb-keeper'})`
- `Agent({name: 'code-analyst', subagent_type: 'code-analyst'})`
- `Agent({name: 'git-tracer', subagent_type: 'git-tracer'})`
- `Agent({name: 'jira-tracer', subagent_type: 'jira-tracer'})`
- `Agent({name: 'synthesizer', subagent_type: 'synthesizer'})`

不 spawn dongmei-ma。

## 3. spawn 后 MCP 交叉确认

要求 git-tracer 调用 `mcp__github__get_me`、jira-tracer 调用 `mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources` 各一次并回报：

- 均成功 → 进入步骤 4。
- 任一报不可用 → 终止；输出「⚠️ <agent> 未继承 MCP。关闭本会话，确认 `/mcp` 全部 ✔ connected 后用普通 `claude` 重跑 `/dm-start`」；不进入查询。

## 4. 就绪门控（30s 超时）

收齐 5 人报到后输出就绪汇总（各成员 ✅/⚠️）：

- kb-keeper 超时 → `kbAvailable=false`，跳过，后续报到自动恢复。
- 其余 4 人超时 → 汇报等待名单。

## 5. 回归协调者

按 `dongmei-ma.md` 核心职责驱动链路。无任务时静默。
