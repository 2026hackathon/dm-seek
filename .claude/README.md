# dm-seek 团队配置（.claude/）— 安全与独占诚实声明

本目录是马冬梅计划（dm-seek）的 Claude Code 成品 team 配置：`agents/`（7 个 agent 定义）+ `skills/`（项目级 skills 布局）。完整导入/配置说明见配置包根的 `README.md`；本文件聚焦**必须诚实告知用户的安全与独占边界**（独占机制规则见 `.claude/rules/runtime-spec.md` §4.2）。

## 运行形态：agent team（teammate）

**启动**：运行 `claude --agent dongmei-ma`——主会话即是协调者 `dongmei-ma`（`agents/dongmei-ma.md`，兼任团队启动器，无中间层），首次启动一次性建团 + 召唤其余 6 个 teammate，随后回归协调者、直接与用户对话。`initialPrompt` 自动启动已通过运行验证。

7 个 agent 为**平级 teammate**，经**共享任务列表 + 消息**协作；`dongmei-ma` 是**协调者 teammate**（非父节点、非 subagent 委派者）。Claude Code 官方语义下，teammate **不应用** subagent frontmatter 的 `mcpServers` / `skills` 字段——它们从 **project/user settings 加载**（与常规会话相同）。因此：

- **GitHub MCP（双轨）**：
  - **路径A（推荐，有浏览器）**：`gh` CLI 扩展 `shuymn/gh-mcp`，通过 `gh auth login` 浏览器 OAuth 认证，token 由 `gh` CLI keyring 管理。`.mcp.json` 配置为 `command: gh` + `args: [mcp]`。
  - **路径B（备选，headless/无浏览器）**：Copilot 托管 MCP（`https://api.githubcopilot.com/mcp`），通过 `${GITHUB_TOKEN}` PAT 环境变量认证。`.mcp.json` 配置为 `type: http` + Bearer header。
  - 两条路径互斥二选一（同一 server 名 `github`），工具前缀均为 `mcp__github__*`。
- **Jira MCP**：Atlassian Plugin（`/plugin install atlassian@claude-plugins-official` → `/mcp` OAuth 授权）。
- 凭据零明文：GitHub 路径A token 由 `gh` CLI keyring 管理（`.mcp.json` 零凭据），路径B 通过 `${GITHUB_TOKEN}` 环境变量占位（`.mcp.json` 不写明文 token）；Jira OAuth token 由 Claude Code keychain 加密存储。
- skills 放在**项目级 `.claude/skills/`**（不写进 agent frontmatter，写了也被忽略）。

## 独占是策略级约束，不是物理隔离（诚实声明，硬性）

> **重要：本配置包对信息源的「独占」是策略级（agent `tools` 白名单）约束，不是进程级物理隔离。**

- MCP server 在**会话层面对全 team 可见**。
- 「GitHub MCP 独占 `repo-tracer`、Jira MCP 独占 `jira-tracer`、其他 agent 不直连信息源」靠**各 agent 定义的 `tools` 白名单**实现：
  - 仅 `repo-tracer` 的 `tools` 含 `mcp__github__*`（GitHub MCP 只读子集，双轨统一工具前缀）；
  - 仅 `jira-tracer` 含 `mcp__atlassian__*`（Atlassian Plugin，只读子集，仅 Jira get/search）；
  - 仅 `kb-keeper` 含 obsidian / Knowlery（KB 读写）路径；
  - `dongmei-ma` 及 `code-analyst` / `synthesizer` / `evidence-verifier` 的 `tools` **不含**任何源类 `mcp__` 工具。

### 独占机制（软边界，诚实声明）

经 H3 端到端实测证实（Claude Code 2.1.177 + gh-mcp）：**L1 `tools` 白名单对简单 agent（body < ~40 行）生效，但对 dm-seek 全部 agent（body > ~50 行）不生效**。因此 dm-seek 的独占不依赖 L1 技术强制，而是依赖 **L2 声明层**（每 agent 边界声明区块）+ **L3 evidence-verifier 校验** 构成软边界。可用 `--strict-mcp-config` 强制屏蔽所有 mcp 工具（但同时阻止合法的 repo-tracer，需取舍）。

经核实 Claude Code 官方设置语义：**`deniedMcpServers` / `disabledMcpjsonServers` 等 MCP server 级策略都是会话级 / 组织级「一刀切」，没有 per-agent / per-teammate 粒度**。因此**不挂 `deniedMcpServers`**做兜底。

---

完整角色表、目录结构、导入与配置步骤见根 `README.md`；运行时规则见 `.claude/rules/` 下各文档。
