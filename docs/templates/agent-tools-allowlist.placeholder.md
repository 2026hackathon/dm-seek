# 占位模板 — 各 agent 的 tools 白名单（路径 B 独占承重点）

用途：task #8 骨架时填入各 `.claude/agents/*.md` 的 `tools` frontmatter 字段。
规则见 `docs/design-mcp-config-shape.md`（路径 B 版）§1、§7。

> 路径 B 下，源独占**唯一**靠各 agent 的 `tools` 白名单实现（`tools` 对 teammate 生效；`mcpServers`/`skills` 不生效）。
> 这是**策略级**约束、**非物理隔离**——MCP 在会话层对全 team 可见，靠白名单约束谁能调用。**交付文档须诚实声明这一点。**

| agent | tools 白名单应含 | 不得含 |
| --- | --- | --- |
| **repo-tracer** | 本地 git 所需 `Bash` + 全部 `mcp__github-<repoSlug>__*`（N 仓逐个 / 前缀） | 任何 `mcp__jira*`、obsidian/KB 写路径 |
| **jira-tracer** | `mcp__jira__jira_get`（**仅只读**，见 design-jira-mcp-toolmap.md） | `mcp__jira__jira_post/put/patch/delete`、任何 `mcp__github-*` |
| **kb-keeper** | `Bash`（调 obsidian CLI）+ `Skill`（调 Knowlery /ask /cook）+ `Read`（读自身配置） | 任何 `mcp__github-*` / `mcp__jira*`（不直连代码/Jira 源） |
| **code-analyst** | 本地直读所需 `Read`/`Grep`/`Glob`；远端取码经 repo-tracer（消息协作，不直连 MCP） | 任何 `mcp__github-*` / `mcp__jira*`（远端取码委托 repo-tracer） |
| **dongmei-ma** | 编排/协作类工具（消息、任务）；**不含任何源类 `mcp__`** | 任何 `mcp__github-*` / `mcp__jira*` / obsidian 直接读写（不直连信息源） |
| **synthesizer** | 综合所需（读上游产物）；不直连源 | 任何源类 `mcp__` |
| **evidence-verifier** | 校验所需（读上游产物）；不直连源 | 任何源类 `mcp__` |

注意事项：
- 工具引用名 `mcp__<serverName>__<toolName>`，整服务前缀 `mcp__<serverName>`。
- 引导 skill（task #15）新增仓库时，须同步把对应 `mcp__github-<repoSlug>__*` 追加进 repo-tracer 的 tools 白名单。
- **L2 强制声明区块（用户裁决，每个 agent 必含）**：除上表 L1 白名单外，每个 agent 的 description/system prompt 必须含固定声明区块（职责范围 / 允许使用的 MCP 服务 / 边界约束硬性「禁调领域外 mcp__、跨域经消息/任务列表请求 owner」）。模板与各 agent 取值见 design-mcp-config-shape.md §1.2.2。
- **独占口径（用户裁决）**：L1 白名单 + L2 声明区块 + evidence-verifier 兜底；**不挂 `deniedMcpServers`**（非 per-agent、会误伤）。**L1 白名单对 session 级 mcp__ 工具的屏蔽机制已由真实 CLI 正面佐证**（`--agent` 启动会话工具集 = 精确白名单、`mcp__` 受其管辖）；**live 端到端演示待部署环境 TC-7.6**（归 T16/qa）——机制已佐证 ≠ live 已坐实，不写已完成 live 坐实/已生效/已失败。
