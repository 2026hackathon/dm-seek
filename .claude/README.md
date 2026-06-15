# dm-seek 团队配置（.claude/）— 安全与独占诚实声明

本目录是马冬梅计划（dm-seek）的 Claude Code 成品 team 配置：`agents/`（7 个 agent 定义）+ `skills/`（项目级 skills 布局）。完整导入/配置说明见配置包根的 `README.md`；本文件聚焦**必须诚实告知用户的安全与独占边界**（独占机制规则见 `.claude/rules/runtime-spec.md` §4.2）。

## 运行形态：agent team（teammate）

**启动**：运行 `claude --agent dongmei-ma`——主会话即是协调者 `dongmei-ma`（`agents/dongmei-ma.md`，兼任团队启动器，无中间层），首次启动一次性建团 + 召唤其余 6 个 teammate，随后回归协调者、直接与用户对话。`initialPrompt` 自动启动已通过运行验证。

7 个 agent 为**平级 teammate**，经**共享任务列表 + 消息**协作；`dongmei-ma` 是**协调者 teammate**（非父节点、非 subagent 委派者）。Claude Code 官方语义下，teammate **不应用** subagent frontmatter 的 `mcpServers` / `skills` 字段——它们从 **project/user settings 加载**（与常规会话相同）。因此：

- 核心 MCP（GitHub 多仓 + Jira）写在**共享 `.mcp.json`**（会话级，全 team 可见）。
- skills 放在**项目级 `.claude/skills/`**（不写进 agent frontmatter，写了也被忽略）。

## 独占是策略级约束，不是物理隔离（诚实声明，硬性）

> **重要：本配置包对信息源的「独占」是策略级（agent `tools` 白名单）约束，不是进程级物理隔离。**

- 共享 `.mcp.json` 里的 MCP server 在**会话层面对全 team 可见**。
- 「GitHub MCP 独占 `repo-tracer`、Jira MCP 独占 `jira-tracer`、其他 agent 不直连信息源」靠**各 agent 定义的 `tools` 白名单**实现——只有被授予对应 `mcp__` 工具的 agent 能调用：
  - 仅 `repo-tracer` 的 `tools` 含 `mcp__dm-github-<repoSlug>__*`；
  - 仅 `jira-tracer` 含 `mcp__jira__jira_get`（**只读**，不授予写工单的工具）；
  - 仅 `kb-keeper` 含 obsidian / Knowlery（KB 读写）路径；
  - `dongmei-ma` 及 `code-analyst` / `synthesizer` / `evidence-verifier` 的 `tools` **不含**任何源类 `mcp__` 工具。
- 这是**策略约束**：白名单对 teammate 生效，未列某 `mcp__` 工具的 agent 不会调用它。但它**不是物理沙箱**。

### per-agent 独占只有 L1 一层（机制边界，诚实声明）

经核实 Claude Code 官方设置语义（settings 文档逐字核对）：**`deniedMcpServers` / `disabledMcpjsonServers` 等 MCP server 级策略都是会话级 / 组织级「一刀切」，没有 per-agent / per-teammate 粒度**。因此：

- **per-agent 独占的唯一「硬」机制 = 各 agent 的 `tools` 白名单（L1）**。**不能用 `deniedMcpServers` 做兜底**——它是组织级/会话级一刀切、无 per-agent 粒度，会**连合法的 `repo-tracer`/`jira-tracer` 一起禁掉**使系统不可用。故本配置包**不挂 `deniedMcpServers`**。
- 部署方可选的 org 治理（非 per-agent 独占）：`managed-settings.json` 用 `allowedMcpServers` 锁定「只允许计划内 `github-*` / `jira`」防越界新增，不误伤授权 agent。

### 承重假设验证状态

| 测试项 | 内容 | 状态 |
| --- | --- | --- |
| TC-7.6 | L1 tools 白名单对会话级 mcp__ 工具的屏蔽有效性 | **已验证通过**（用户真实环境运行验证） |
| TC-7.7 | dongmei-ma initialPrompt 自动启动 | **已验证通过**（用户真实环境运行验证） |


## 凭据零明文

任何配置文件（`.mcp.json` / agent `.md` / settings）只允许 `${DMSEEK_*}` 占位，**绝不出现真实 token**。凭据全在 OS 环境变量，由引导/配置 skill 协助用户在各自平台设置。请勿提交含真实 token 的临时设置脚本。

---

完整角色表、目录结构、导入与配置步骤见根 `README.md`；运行时规则与设计定稿见 `.claude/rules/` 下各文档（`runtime-spec.md` 运行时规则 + `design-*.md` 设计定稿）。
