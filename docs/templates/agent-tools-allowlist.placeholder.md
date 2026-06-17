# 占位模板 — 各 agent 的 tools 白名单（独占承重点）

用途：填入各 `.claude/agents/*.md` 的 `tools` frontmatter 字段。

> teammate 形态下，源独占**唯一**靠各 agent 的 `tools` 白名单实现（`tools` 对 teammate 生效；`mcpServers`/`skills` 不生效）。
> 这是**策略级**约束、**非物理隔离**——MCP 在会话层对全 team 可见，靠白名单约束谁能调用。
>
> GitHub MCP 由 `官方 GitHub MCP` 提供（`.mcp.json` command 类型，server `github`）；Jira 由 Atlassian Plugin 提供（server `atlassian`）。dm-seek 仅在各 agent 白名单中加入对应 `mcp__` 工具前缀（只读子集）。

| agent | tools 白名单应含 | 不得含 |
| --- | --- | --- |
| **repo-tracer** | 本地 git 所需 `Bash` + `官方 GitHub MCP` 只读子集 `mcp__github__*`（仅 get/search 工具） | 任何 `mcp__github__create*`/`delete*`/`push*`/`commit*`/`merge*`/`fork*` 等写工具、任何 `mcp__atlassian*`、obsidian/KB 写路径 |
| **jira-tracer** | 官方 Atlassian plugin 只读子集 `mcp__atlassian__*`（仅 Jira get/search 工具） | `mcp__atlassian__add*`/`create*`/`transition*`/`update*` 等写工具、任何 `mcp__github*` |
| **kb-keeper** | `Bash`（调 obsidian CLI）+ `Skill`（调 Knowlery /ask /cook）+ `Read`（读自身配置） | 任何 `mcp__github*` / `mcp__atlassian*`（不直连代码/Jira 源） |
| **code-analyst** | 本地直读所需 `Read`/`Grep`/`Glob` + `Bash`（**仅本地仓 git 历史**，态B）；远端取码经 repo-tracer（消息协作，不直连 MCP） | 任何 `mcp__github*` / `mcp__atlassian*`（远端取码/远端历史委托 repo-tracer；`Bash` 禁用于任何远端操作） |
| **dongmei-ma** | 编排/协作类工具（消息、任务）；**不含任何源类 `mcp__`** | 任何 `mcp__github*` / `mcp__atlassian*` / obsidian 直接读写（不直连信息源） |
| **synthesizer** | 综合所需（读上游产物）；不直连源 | 任何源类 `mcp__` |
| **evidence-verifier** | 校验所需（读上游产物）；不直连源 | 任何源类 `mcp__` |

注意事项：
- 工具引用名 `mcp__<serverName>__<toolName>`，整服务前缀 `mcp__<serverName>`。server 名为 `github` / `atlassian`（双下划线 `__` 分隔）。
- **声明区块（每个 agent 必含）**：每个 agent 的 description/system prompt 必须含固定声明区块（职责范围 / 允许使用的 MCP 服务 / 边界约束硬性「禁调领域外 mcp__、跨域经消息/任务列表请求 owner」）。
- **独占口径（v0.4.4）**：声明层 + 校验层（evidence-verifier 兜底）；L1 tools 白名单已降级为设计意图文档（body > ~40 行时不生效）；**不挂 `deniedMcpServers`**（非 per-agent、会误伤）。
- GitHub：`官方 GitHub MCP` 通过 `.mcp.json` command 类型配置（server `github`）；Jira：Atlassian Plugin 自行注册（server `atlassian`）。repo-tracer 的 tools 白名单含 `mcp__github__*`（只读子集）；jira-tracer 的 tools 白名单含 `mcp__atlassian__*`（只读子集）。
- MCP server 暴露的工具集含写操作（create/update/delete/comment 等），dm-seek 必须在白名单中精标只读子集——不授予任何写工具。
