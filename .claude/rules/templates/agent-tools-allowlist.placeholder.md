# 占位模板 — 各 agent 的 tools 白名单（独占承重点）

用途：填入各 `.claude/agents/*.md` 的 `tools` frontmatter 字段。
规则见 `../design-mcp-config-shape.md` §1。

> teammate 形态下，源独占**唯一**靠各 agent 的 `tools` 白名单实现（`tools` 对 teammate 生效；`mcpServers`/`skills` 不生效）。
> 这是**策略级**约束、**非物理隔离**——MCP 在会话层对全 team 可见，靠白名单约束谁能调用。**交付文档须诚实声明这一点。**

| agent | tools 白名单应含 | 不得含 |
| --- | --- | --- |
| **repo-tracer** | 本地 git 所需 `Bash` + 官方 GitHub plugin 只读子集 `mcp__github__*`（OAuth 优先）+ PAT fallback 全部 `mcp__dm-github-<repoSlug>__*`（N 仓逐个 / 前缀） | 任何 `mcp__github__create_*`/`delete_*`/`commit_*` 等写工具、任何 `mcp__atlassian*`/`mcp__jira*`、obsidian/KB 写路径 |
| **jira-tracer** | 官方 Atlassian plugin 只读子集 `mcp__atlassian__*`（OAuth 优先，仅 Jira get/search 工具）+ PAT fallback `mcp__jira__jira_get`（**均只读**） | `mcp__atlassian__add*`/`create*`/`transition*`/`update*` 等写工具、`mcp__jira__jira_post/put/patch/delete`、任何 `mcp__github-*` |
| **kb-keeper** | `Bash`（调 obsidian CLI）+ `Skill`（调 Knowlery /ask /cook）+ `Read`（读自身配置） | 任何 `mcp__github-*` / `mcp__jira*`（不直连代码/Jira 源） |
| **code-analyst** | 本地直读所需 `Read`/`Grep`/`Glob` + `Bash`（**仅本地仓 git 历史**，态B）；远端取码经 repo-tracer（消息协作，不直连 MCP） | 任何 `mcp__github-*` / `mcp__jira*`（远端取码/远端历史委托 repo-tracer；`Bash` 禁用于任何远端操作） |
| **dongmei-ma** | 编排/协作类工具（消息、任务）；**不含任何源类 `mcp__`** | 任何 `mcp__github-*` / `mcp__jira*` / obsidian 直接读写（不直连信息源） |
| **synthesizer** | 综合所需（读上游产物）；不直连源 | 任何源类 `mcp__` |
| **evidence-verifier** | 校验所需（读上游产物）；不直连源 | 任何源类 `mcp__` |

注意事项：
- 工具引用名 `mcp__<serverName>__<toolName>`，整服务前缀 `mcp__<serverName>`。
- 引导 skill 新增仓库时，须同步把对应 `mcp__dm-github-<repoSlug>__*` 追加进 repo-tracer 的 tools 白名单。
- **L2 强制声明区块（每个 agent 必含）**：除上表 L1 白名单外，每个 agent 的 description/system prompt 必须含固定声明区块（职责范围 / 允许使用的 MCP 服务 / 边界约束硬性「禁调领域外 mcp__、跨域经消息/任务列表请求 owner」）。模板与各 agent 取值见 ../design-mcp-config-shape.md §1.1.2。
- **独占口径**：L1 白名单 + L2 声明区块 + evidence-verifier 兜底；**不挂 `deniedMcpServers`**（非 per-agent、会误伤）。L1 白名单对 session 级 mcp__ 工具的屏蔽机制已正面佐证。
- Plugin (OAuth) 模式：官方 GitHub / Atlassian plugin 自行注册 MCP server（不经过 .mcp.json）。repo-tracer 的 tools 白名单须同时含官方 plugin 只读子集（`mcp__github__*`）和 PAT fallback（`mcp__dm-github-<repoSlug>__*`）；jira-tracer 须同时含 `mcp__atlassian__*`（只读子集）和 `mcp__jira__jira_get`。运行时优先走 plugin tools，连接失败回退 PAT。
- 官方 plugin 暴露的工具集含写操作（create/update/delete/comment 等），dm-seek 必须在白名单中精标只读子集——不授予任何写工具。具体只读工具清单见 `../design-mcp-config-shape.md` §8.7。
