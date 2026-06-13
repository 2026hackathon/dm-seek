# dm-seek 团队配置（.claude/）— 安全与独占诚实声明

本目录是马冬梅计划（dm-seek）的 Claude Code 成品 team 配置：`agents/`（7 个首版 agent 定义）+ `skills/`（项目级 skills 布局）。完整导入/配置说明见配置包根的 `README.md`；本文件聚焦**必须诚实告知用户的安全与独占边界**（独占机制规则见 `.claude/rules/runtime-spec.md` §4.2、测试计划 TC-7.7）。

## 运行形态：agent team（路径 B，teammate）

7 个 agent 为**平级 teammate**，经**共享任务列表 + 消息**协作；`dongmei-ma` 是**协调者 teammate**（非父节点、非 subagent 委派者）。Claude Code 官方语义下，teammate **不应用** subagent frontmatter 的 `mcpServers` / `skills` 字段——它们从 **project/user settings 加载**（与常规会话相同）。因此：

- 核心 MCP（GitHub 多仓 + Jira）写在**共享 `.mcp.json`**（会话级，全 team 可见）。
- skills 放在**项目级 `.claude/skills/`**（不写进 agent frontmatter，写了也被忽略）。

## 独占是策略级约束，不是物理隔离（诚实声明，硬性）

> **重要：本配置包对信息源的「独占」是策略级（agent `tools` 白名单）约束，不是进程级物理隔离。**

- 共享 `.mcp.json` 里的 MCP server 在**会话层面对全 team 可见**。
- 「GitHub MCP 独占 `repo-tracer`、Jira MCP 独占 `jira-tracer`、其他 agent 不直连信息源」靠**各 agent 定义的 `tools` 白名单**实现——只有被授予对应 `mcp__` 工具的 agent 能调用：
  - 仅 `repo-tracer` 的 `tools` 含 `mcp__github-<repoSlug>__*`；
  - 仅 `jira-tracer` 含 `mcp__jira__jira_get`（**只读**，不授予写工单的工具）；
  - 仅 `kb-keeper` 含 obsidian / Knowlery（KB 读写）路径；
  - `dongmei-ma` 及 `code-analyst` / `synthesizer` / `evidence-verifier` 的 `tools` **不含**任何源类 `mcp__` 工具。
- 这是**策略约束**：白名单对 teammate 生效，未列某 `mcp__` 工具的 agent 不会调用它。但它**不是物理沙箱**。

### per-agent 独占只有 L1 一层（机制边界，诚实声明）

经核实 Claude Code 官方设置语义（settings 文档逐字核对）：**`deniedMcpServers` / `disabledMcpjsonServers` 等 MCP server 级策略都是会话级 / 组织级「一刀切」，没有 per-agent / per-teammate 粒度**。因此：

- **per-agent 独占的唯一「硬」机制 = 各 agent 的 `tools` 白名单（L1）**。当前 Claude Code 里**只有 L1 这一层能做 per-agent 独占**（其对 `mcp__` 工具的屏蔽机制已由真实 CLI 正面佐证、live 端到端演示待部署环境，见下）。**不能用 `deniedMcpServers` 做兜底**——它是组织级/会话级一刀切、无 per-agent 粒度，会**连合法的 `repo-tracer`/`jira-tracer` 一起禁掉**使系统不可用。故本配置包**不挂 `deniedMcpServers`**，也**不存在「三层硬兜底」**。
- 配套的**软隔离/可审计层**（非硬阻止、不替代 L1）：① 每个 agent 定义内的**边界声明区块**（`职责范围 / 允许使用的 MCP 服务 / 边界约束`）——靠角色自律约束越界；② **evidence-verifier 边界违规校验**——结论若引用产出方声明范围外的工具/来源则标记违规。这两层让越界**可被发现、可审计**，但**不能在引擎层硬阻止调用**——硬阻止只有 L1（其屏蔽机制已获真实 CLI 正面佐证、live 演示待部署环境，见下）。
- 部署方可选的 org 治理（非 per-agent 独占）：`managed-settings.json` 用 `allowedMcpServers` 锁定「只允许计划内 `github-*` / `jira`」防越界新增，不误伤授权 agent。

### 承重假设与运行时验证（TC-7.6）

- 「L1 `tools` 白名单能否真正屏蔽会话级已加载的 `mcp__` 工具」是 per-agent 独占成立的**唯一承重假设**。
- 设计层依据：官方文档「the teammate honors that definition's `tools` allowlist... even when `tools` restricts other tools」（agent-teams 文档逐字）。
- baseline 实测（已坐实）：未受限的 teammate **能**调用会话级已加载的 MCP 工具（以 `mcp__ide__getDiagnostics` 为样本实测，正常返回）——证实 MCP 对全 team 会话级可见、独占不能靠「隐藏」。
- 屏蔽侧运行时验证：见下「用户侧 TC-7.6 验证步骤」，端到端验证（T16）必做项。
- **当前状态 = 机制已正面佐证、live 端到端演示待部署环境**（2026-06-12 team-lead 用真实 `claude` CLI 2.1.165 当场实测）：
  - 以 `claude -p --agent repo-tracer --strict-mcp-config --mcp-config <临时 github 配置>` 启动真实会话，该会话可用工具 = **精确的 `[Bash, Read, SendMessage]`（非默认全量工具集）**——**证实真实 Claude Code 确实强制 agent frontmatter 的 `tools` 白名单且为「包含式」、`mcp__` 工具受同一白名单管辖**（repo-tracer 须**显式声明** `mcp__github-hdr-delivery-project` 方可获得它）。逻辑推论：不声明 mcp 工具的 agent（synthesizer / dongmei-ma 等）运行时即无任何 `mcp__` 工具 = **L1 屏蔽成立**。
  - 此实测**推翻了**早先 harness 探针「白名单可能未生效」的疑虑——那次是中途 spawn 路径未施加白名单（teammate 仍拿全量工具），是 spawn 路径问题、**非引擎不支持**；真实 CLI 下白名单确实生效。
  - **唯一仍待补 = 「live mcp 工具存在却被白名单挡住」的端到端负向演示**：本会话连不上 live MCP（github Copilot 托管 MCP 用 `ghp_` PAT 在 headless 下未连上、多半需订阅/OAuth；本地 MCP 包被权限策略拦截），故该帧留**部署环境**（下方用户侧步骤 / T16）——它是上述已证机制的**直接推论**，非新的未知。
- **若 TC-7.6 证伪 L1**（白名单挡不住会话级 mcp 工具）：则 Claude Code 当前**无任何 per-agent MCP 硬独占机制**，此为引擎能力约束——降级为**软隔离**（角色/prompt 约束「该 agent 不得调用源类 MCP」+ evidence-verifier 出处校验兜底），并须升级团队/用户决策（接受软隔离 或 等 Claude Code 增强 per-agent MCP 隔离）。**不假装有硬兜底。**

### 用户侧 TC-7.6 验证步骤（导入后自验，推荐）

在你自己接了真实 MCP 的环境里坐实 L1：

1. 导入 dm-seek 配置包，按根 `README.md` 配好至少一个真实可连的 MCP（如某仓 GitHub token）。
2. 启动 dm-seek agent team。
3. 让一个 `tools` 白名单**不含** `mcp__github-*` 的 teammate（如 `synthesizer`）尝试调用 `mcp__github-<repoSlug>__*` 工具。
4. 观测结果：
   - **被拒 / 不可用** → L1 屏蔽成立，per-agent 独占有效（通过）。
   - **能调用成功** → L1 对 mcp 工具不生效 → 触发上述能力约束升级；此时退到「策略级软隔离」并向团队/用户报告。

## 凭据零明文

任何配置文件（`.mcp.json` / agent `.md` / settings）只允许 `${DMSEEK_*}` 占位，**绝不出现真实 token**。凭据全在 OS 环境变量，由引导/配置 skill 协助用户在各自平台设置。请勿提交含真实 token 的临时设置脚本。

---

完整角色表、目录结构、导入与配置步骤见根 `README.md`；运行时规则与设计定稿见 `.claude/rules/` 下各文档（`runtime-spec.md` 运行时规则 + `design-*.md` 设计定稿）。
