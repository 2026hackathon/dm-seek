# 设计 — 多仓 GitHub MCP 配置形态 + repo-tracer 独占授权 + 凭据环境变量化

| 项目 | 内容 |
| --- | --- |
| 文档 | design-mcp-config-shape.md（设计/契约） |
| owner | tools-dev |
| 对应任务 | #3（设计期），下游依赖 #8 团队骨架、#12 repo-tracer、#13 jira-tracer、#15 引导/配置 skill |
| 依据 | 马冬梅计划-PRD v0.4（§6.1/6.2 归属约束、§9 MCP 选型、§11.4 多仓配置复杂度）+ 运行形态裁决：**路径 B（agent team teammate 形态）** |
| 平台 | Windows + macOS |
| 状态 | **已按路径 B 重做**（v0.3 内联独占版作废），待 critic 审视 |

> 本文是 MCP 配置形态的**权威契约**：`.mcp.json` 占位、独占授权机制、凭据环境变量化口径、`${VAR}` 命名约定、跨平台设置说明。所有数值/路径/token 一律占位，**绝不出现真实凭据**。
>
> **⚠️ 形态变更说明**：本项目交付物是**一支真正的 agent team**（7 个平级 teammate + 共享配置），即运行形态 = **路径 B**。Claude Code 官方文档明确：**agent team 的 teammate 不应用 subagent frontmatter 的 `mcpServers` / `skills` 字段，teammate 从 project/user settings（含共享 `.mcp.json`）加载 MCP 与 skills，与常规会话相同。** 因此 v0.3 文档「把 MCP 内联进 agent frontmatter 实现物理独占」的方案**在本形态下失效、已作废**。本版改为：MCP 写**共享 `.mcp.json`**，独占靠**各 agent `tools` 白名单**（策略级），并诚实声明其为策略约束、非物理隔离。

---

## 0. 关键结论（TL;DR）

1. **核心 MCP 写共享 `.mcp.json`**（会话级，所有 teammate 都会连接）。**不走** agent frontmatter 内联（teammate 形态下被忽略，会静默失效）。
2. **独占 = 策略级，靠各 agent 定义的 `tools` 白名单实现**（`tools` 字段对 teammate 仍生效）：
   - 仅 **repo-tracer** 的 `tools` 含 GitHub MCP 工具（`mcp__github-<repoSlug>__*`，N 个）；
   - 仅 **jira-tracer** 含 Jira MCP 工具（仅 `mcp__jira__jira_get`，只读）；
   - 仅 **kb-keeper** 含 KB/obsidian 读写路径；
   - **dongmei-ma** 及其余 agent 的 `tools` **不含**任何源类 `mcp__` 工具 → 满足「不直连信息源」。
3. **每仓一个命名实例**：`github-<repoSlug>`（一个 MCP 服务 ↔ 一个 git repo ↔ 一个独立 token），N 仓即 `.mcp.json` 里 N 个条目。
4. **Jira MCP** 单实例，server 名固定 `jira`；该 server 是**通用 HTTP 透传型**（仅 `jira_get/post/put/patch/delete` 5 个工具），详见 `design-jira-mcp-toolmap.md`。
5. **凭据硬性环境变量化**：所有 token / URL / 邮箱一律 `${VAR}` 引用，**绝不明文落任何配置文件**。`.mcp.json` 原生支持 `${VAR}` 与 `${VAR:-default}` 展开（位点含 `url`、`headers`、`command`、`args`、`env`）。
6. **诚实声明（硬性，用户裁决口径）**：交付文档与 README 必须写明「源独占 = **L1 工具白名单 + L2 声明区块 + evidence-verifier 兜底**；会话层面 MCP 对全 team 可见，靠白名单 + 声明约束谁能调用。**L1 白名单对 session 级 mcp__ 工具的屏蔽机制已由真实 CLI 正面佐证**（实测 `--agent` 启动会话工具集 = 精确白名单、`mcp__` 受其管辖）；**live 端到端演示待部署环境 TC-7.6**——机制已佐证 ≠ live 已坐实，不写「已完成 live 坐实/已生效/已失败」。**不挂 `deniedMcpServers`**（非 per-agent、会误伤）」。
7. **引导/配置 skill** 负责：探测本地多仓（非敏感）→ 生成 `${VAR}` 命名清单 → 引导用户设置环境变量（敏感项手填）→ 把 server 块写入**共享 `.mcp.json`** + 把对应 `mcp__` 工具写进 **repo-tracer / jira-tracer 的 `tools` 白名单**。

---

## 1. 独占授权机制（核心，路径 B）

### 1.0 决策记录：路径 A vs 路径 B（保留以备追溯）

| 维度 | 路径 A（subagent 形态，**未采用**） | 路径 B（agent team teammate 形态，**本项目采用**） |
| --- | --- | --- |
| 交付形态 | 主会话 + 经 Agent 工具委派的 subagent | 一支真正的 agent team（7 个平级 teammate + 共享配置） |
| MCP 落点 | 内联各 agent frontmatter `mcpServers` | 共享 `.mcp.json`（会话级） |
| skills 落点 | 可内联 frontmatter `skills` 预加载 | 项目级 `.claude/skills/` |
| 独占强度 | **物理独占**（其他 agent 看不到该 server） | **策略级独占**（全 team 可见，靠 `tools` 白名单约束谁能调用） |
| 独占机制依据 | sub-agents 文档：内联 server 父对话/他者拿不到 | agent-teams 文档：teammate honors `tools` allowlist；`mcpServers`/`skills` frontmatter 不生效（见 §1.2.1） |

> **裁决（2026-06-12，用户）**：选**路径 B**——以「策略级独占」换取「真正的 agent team」交付形态。本文正文一律以路径 B 为准；路径 A 仅作对照记录，不再作为实现依据。PRD 已据此更新到 v0.4（task #17）。

### 1.1 为什么靠 `tools` 白名单而非内联

Claude Code 官方语义（双向核实）：

- **subagent 形态**：MCP server 内联进 subagent frontmatter `mcpServers` → 父对话/其他 agent 拿不到（物理独占）。**——这是路径 A 的机制，本项目未采用。**
- **agent team teammate 形态（本项目）**：官方文档 Note 原文——「The `skills` and `mcpServers` frontmatter fields in a subagent definition are NOT applied when that definition runs as a teammate. Teammates load skills and MCP servers from project/user settings, same as a regular session.」即 **teammate 没有 per-teammate 的 MCP 独占机制**；frontmatter 的 `mcpServers`/`skills` 不生效。

> 因此本形态下，「独占于 repo-tracer」只能靠**每个 agent 定义的 `tools` 白名单**（`tools` 对 teammate 仍生效）：MCP 在会话层对所有 teammate 可见，但只有 `tools` 列了对应 `mcp__` 工具的 agent 才能实际调用。这是**策略约束，非物理隔离**，必须诚实声明。

### 1.2 双层边界 + 兜底（路径 B，用户 2026-06-12 最终裁决）

> **用户最终裁决（维持路径 B）**：独占 = **L1 工具白名单 + L2 声明区块（强制规范）+ evidence-verifier 兜底**。**不挂 `deniedMcpServers`**——它非 per-agent、对全会话统一生效会误伤其他 agent。

| 层 | 机制 | 作用 |
| --- | --- | --- |
| L1 工具白名单（主、承重） | 各 agent `tools` 字段精确列出其可用 `mcp__` 工具（本域）；非授权 agent 不列 | 逐 agent 独占的技术手段（teammate 形态下 `tools` 生效） |
| L2 声明区块（强制规范） | 每个 agent 的 description/system prompt **必须含固定声明区块**（职责范围 / 允许使用的 MCP 服务 / 边界约束硬性），见 §1.2.2 | 行为层强约束 + 跨域走消息/任务列表请求 owner，不直调领域外 MCP |
| 兜底 | evidence-verifier 校验 | 结论出处校验兜底——越域取数/无出处会被校验拦截 |

> **L1 为承重技术防线、L2 为行为规范**。L1 是「正向授权」——靠「只给该给的 agent 列工具」，而非「禁其他 agent」。**不引入 `deniedMcpServers`**（会误伤）。

#### 1.2.2 强制声明区块（每个 agent 必含，用户裁决）

每个 agent 定义除 L1 `tools` 白名单外，**必须在 description/system prompt 加入固定声明区块**：

```
## 职责范围
<负责什么>
## 允许使用的 MCP 服务
<明确列出；无则写「无」>
## 边界约束（硬性）
禁止调用本职责范围外的任何 MCP 服务(mcp__*)。需要跨域数据时，经任务列表/消息向对应 owner agent 请求，绝不直接调用领域外 MCP。
```

各 agent 的「允许使用的 MCP 服务」取值（供 T8 骨架 + 各实现任务填充）：

| agent | 允许 MCP | 声明区块「允许使用的 MCP 服务」写法 |
| --- | --- | --- |
| repo-tracer | 仅 `mcp__github-<repoSlug>__*`（N 仓） | 列出全部 github-* 系列，注明「不调 jira / 其他 mcp__」 |
| jira-tracer | 仅 `mcp__jira__jira_get`（只读） | 「仅 Jira 只读（jira_get），不写工单、不调 github/其他」 |
| kb-keeper | **无 mcp__**（KB 经 obsidian CLI / Knowlery，非 mcp__ 服务） | 「无 mcp__；KB 经 obsidian CLI / Knowlery；不读源码、不调任何 mcp__ 源服务」 |
| code-analyst | 无（远端取码经 repo-tracer，不直连 MCP） | 「无 mcp__；远端代码经 repo-tracer 取」 |
| dongmei-ma / synthesizer / evidence-verifier | 无 | 「无 mcp__；不直连任何信息源」 |

#### 1.2.1 承重机制依据（官方文档，应 T7 要求）

路径 B 的策略级独占成立，依赖以下两条 Claude Code 官方语义（`code.claude.com/docs/en/agent-teams` §"Use subagent definitions for teammates" 与 §"Context and communication"，逐字核实）：

1. **MCP 对全 team 会话级可见**：「When spawned, a teammate loads the same project context as a regular session: CLAUDE.md, MCP servers, and skills.」→ 共享 `.mcp.json` 的 server 被每个 teammate 连接（这正是为什么不能靠「藏起来」做独占）。
2. **`tools` 白名单对 teammate 生效、用于约束工具**：「The teammate honors that definition's `tools` allowlist and `model`... Team coordination tools such as `SendMessage` and the task management tools are always available to a teammate even when `tools` restricts other tools.」→ teammate 遵守其 subagent 定义的 `tools` 白名单，`tools` 能限制非协调类工具（含 `mcp__*`）；协调工具（SendMessage/任务管理）恒可用、不受限。
3. **`mcpServers`/`skills` frontmatter 对 teammate 不生效**：「The `skills` and `mcpServers` frontmatter fields in a subagent definition are not applied when that definition runs as a teammate.」→ 故 MCP 必须落共享 `.mcp.json`、skills 必须落项目级 `.claude/skills/`，不能内联。
   > **具体受影响的 skill（知会 T6/T14/T15）**：本系统全部 skill——synthesizer 分析方法 skill（T6/T14）、KB-init skill、引导/配置 skill（T15）、kb-keeper 调用的 Knowlery 集成（T10，见 design-kb-init-and-integration.md §3.3）——**一律放项目级 `.claude/skills/`**，由各 teammate 在运行时经 `Skill` 工具（或 obsidian `command`，见 Knowlery 预研）调用，**不得依赖 frontmatter `skills` 预加载**。

> 结论：MCP 在会话层对所有 teammate 加载（条1），但每个 teammate 只能调用其 `tools` 白名单内的 `mcp__` 工具（条2）——**这就是策略级独占的机制承重点**。`tools` 是「honors allowlist」式的正向授权，未列即不可调用。
>
> **残余风险与兜底（口径：L1 屏蔽机制已正面佐证，live 演示待部署环境）**：上述官方文档语义已由真实 CLI 实测正面佐证——`--agent` 启动会话的可用工具集 = 精确白名单（非全量）、`mcp__` 受其管辖，故未列某 `mcp__` 工具的 teammate 运行时无该工具（L1 屏蔽成立，见 §B.3 / `验证-端到端测试报告.md` §9）。**仍待补的 live 端到端演示**（无权 teammate 试调 live mcp 被挡）由 **TC-7.6 运行时**在部署环境补做（归 T16/qa）——**机制已佐证 ≠ live 已坐实，不写「已完成 live 坐实」也不写「已失败」**。纵深防御:除 L1 外仍以 **L2 声明区块（行为规范）+ evidence-verifier 兜底** 共同保障。**不引入 `deniedMcpServers`**（用户裁决：非 per-agent、会误伤其他 agent）。诚实声明口径见 §0.6。

### 1.3 MCP 工具命名规则

引用名：`mcp__<serverName>__<toolName>`，整服务可用 `mcp__<serverName>` 前缀。

- repo-tracer 的 `tools` 含：`mcp__github-<repoSlug>__*`（N 个仓库，逐个或前缀）。
- jira-tracer 的 `tools` 含：`mcp__jira__jira_get`（**仅只读**，不含 post/put/patch/delete，见 `design-jira-mcp-toolmap.md` §1）。
- 其余 agent 的 `tools`：**不出现**任何 `mcp__github-*` / `mcp__jira`。

---

## 2. GitHub MCP — 每仓一命名实例

### 2.1 命名约定（路径 B 下不变）

| 元素 | 约定 | 示例 |
| --- | --- | --- |
| server 名 | `github-<repoSlug>` | `github-hdr-delivery-project` |
| `<repoSlug>` | 取 git remote 仓名，小写，非 `[a-z0-9-]` 字符替换为 `-` | `hdr-delivery-project` |
| token 环境变量 | `DMSEEK_GH_TOKEN_<REPO_SLUG_UPPER>` | `DMSEEK_GH_TOKEN_HDR_DELIVERY_PROJECT` |
| 端点 | 固定 `https://api.githubcopilot.com/mcp/`（GitHub Copilot 托管） | — |

> `<REPO_SLUG_UPPER>` = repoSlug 转大写、`-` 转 `_`。命名稳定可由引导 skill 机械生成，便于批量管理。

### 2.2 server 块形态（写入共享 `.mcp.json`）

```jsonc
// .mcp.json（项目根，共享，N 仓 = N 条 github-* 条目）
{
  "mcpServers": {
    "github-hdr-delivery-project": {
      "type": "http",
      "url": "${DMSEEK_GH_MCP_URL:-https://api.githubcopilot.com/mcp/}",
      "headers": {
        "Authorization": "Bearer ${DMSEEK_GH_TOKEN_HDR_DELIVERY_PROJECT}"
      }
    }
    // 第二个仓库（占位，按 §2.1 推导 server 名 + token 变量名）：
    // "github-<repoSlug-2>": {
    //   "type": "http",
    //   "url": "${DMSEEK_GH_MCP_URL:-https://api.githubcopilot.com/mcp/}",
    //   "headers": { "Authorization": "Bearer ${DMSEEK_GH_TOKEN_<REPO_SLUG_2_UPPER>}" }
    // }
  }
}
```

> 所有实例共用同一端点，**区分仓库靠不同 token**（每个 token 授权到对应 repo）。`type: http` 与 `streamable-http` 等价。**独占由 repo-tracer 的 `tools` 白名单承担**（§1.2），不是靠这里的声明位置。

### 2.3 仓库 ↔ 实例 ↔ token 映射表（引导 skill 维护，供 repo-tracer 路由）

引导 skill 生成一份**非敏感**映射清单（不含 token 值，只含变量名），落 `docs/` 或 KB，供 repo-tracer 把 code-analyst 的 repo+模块映射路由到正确实例：

| repo（本地路径 / remote） | repoSlug | MCP server 名 | token 变量名 |
| --- | --- | --- | --- |
| `D:\dev_repository\hdr-delivery-project` | hdr-delivery-project | `github-hdr-delivery-project` | `DMSEEK_GH_TOKEN_HDR_DELIVERY_PROJECT` |
| …（每仓一行，占位） | … | … | … |

---

## 3. Jira MCP — 单实例（写入共享 `.mcp.json`）

选型：`@aashari/mcp-server-atlassian-jira`（stdio，npx 拉起）。**env 变量名已核实**（见 `design-jira-mcp-toolmap.md` §3，原开放点1关闭）。

```jsonc
// .mcp.json 中的 jira 条目
{
  "mcpServers": {
    "jira": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@aashari/mcp-server-atlassian-jira"],
      "env": {
        "ATLASSIAN_SITE_NAME": "${DMSEEK_JIRA_SITE_NAME}",
        "ATLASSIAN_USER_EMAIL": "${DMSEEK_JIRA_EMAIL}",
        "ATLASSIAN_API_TOKEN": "${DMSEEK_JIRA_API_TOKEN}"
      }
    }
  }
}
```

> 该 server 仅暴露 5 个通用 HTTP 方法工具（`jira_get` 等），靠 REST v3 端点取数；jira-tracer **仅授予 `mcp__jira__jira_get`**（只读）。工具与端点对照见 `design-jira-mcp-toolmap.md`。

---

## 4. 凭据环境变量化（硬性，安全默认）

### 4.1 铁律

- **任何配置文件（`.mcp.json` / agent `.md` / settings）中只允许出现 `${VAR}` 占位，不得出现 token / 密码 / API key 明文。**
- `.mcp.json` 支持：`${VAR}`（取值）、`${VAR:-default}`（缺省回退；**仅用于非敏感项**如端点 URL；敏感项不设 default，缺失即报错而非静默空值）。
- 展开位点：`url`、`headers`、`command`、`args`、`env`。

### 4.2 `${VAR}` 命名总表

| 用途 | 变量名 | 敏感 | 是否可设 default |
| --- | --- | --- | --- |
| 某仓 GitHub token | `DMSEEK_GH_TOKEN_<REPO_SLUG_UPPER>` | 是 | 否 |
| GitHub MCP 端点（如需覆盖） | `DMSEEK_GH_MCP_URL`（默认 `https://api.githubcopilot.com/mcp/`） | 否 | 是 |
| Jira 站点名 | `DMSEEK_JIRA_SITE_NAME` | 否（半敏感） | 否 |
| Jira 邮箱 | `DMSEEK_JIRA_EMAIL` | 半敏感 | 否 |
| Jira API token | `DMSEEK_JIRA_API_TOKEN` | 是 | 否 |
| obsidian CLI 路径（kb-keeper 用） | `DMSEEK_OBSIDIAN_CLI`（跨平台二进制路径） | 否 | 视情况 |
| （二期）Figma | `DMSEEK_FIGMA_*` | 是 | 否 |

> 统一前缀 `DMSEEK_` 避免与用户既有环境变量冲突，且便于一键审计/清理。

### 4.3 跨平台设置说明（占位，引导 skill 生成实际命令）

**Windows（PowerShell，当前会话 + 持久化用户级）**

```powershell
# 当前会话临时（关窗即失）
$env:DMSEEK_GH_TOKEN_HDR_DELIVERY_PROJECT = "<粘贴-token>"
$env:DMSEEK_JIRA_API_TOKEN = "<粘贴-token>"

# 持久化到用户环境变量（重开终端生效；写注册表 HKCU\Environment）
[Environment]::SetEnvironmentVariable("DMSEEK_GH_TOKEN_HDR_DELIVERY_PROJECT", "<粘贴-token>", "User")
[Environment]::SetEnvironmentVariable("DMSEEK_JIRA_API_TOKEN", "<粘贴-token>", "User")
```

**macOS / Linux（bash/zsh）**

```bash
# 当前会话临时
export DMSEEK_GH_TOKEN_HDR_DELIVERY_PROJECT="<粘贴-token>"
export DMSEEK_JIRA_API_TOKEN="<粘贴-token>"

# 持久化：追加到 ~/.zshrc 或 ~/.bashrc（按用户默认 shell）
echo 'export DMSEEK_GH_TOKEN_HDR_DELIVERY_PROJECT="<粘贴-token>"' >> ~/.zshrc
echo 'export DMSEEK_JIRA_API_TOKEN="<粘贴-token>"' >> ~/.zshrc
```

> 引导 skill 应：检测平台与默认 shell，输出对应命令；**不把 token 回显进日志/历史**（PowerShell 持久化用 `[Environment]::SetEnvironmentVariable`；shell 侧提示用户可改用密钥管理器）。**Claude Code 进程须在变量已设的环境中启动**，`${VAR}` 才能展开——引导 skill 须提醒用户「设完变量后重启 Claude Code / 终端」。

---

## 5. 共享 `.mcp.json` 占位（项目根）

> 路径 B：**核心 MCP（GitHub 多仓 + Jira）都写在此**。独占不靠声明位置，靠各 agent `tools` 白名单（§1）。

```jsonc
// .mcp.json（项目根，共享；引导 skill 据探测结果填充）
{
  "mcpServers": {
    // GitHub：每仓一条 github-<repoSlug>（§2.2）
    "github-hdr-delivery-project": {
      "type": "http",
      "url": "${DMSEEK_GH_MCP_URL:-https://api.githubcopilot.com/mcp/}",
      "headers": { "Authorization": "Bearer ${DMSEEK_GH_TOKEN_HDR_DELIVERY_PROJECT}" }
    },
    // Jira：单实例（§3）
    "jira": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@aashari/mcp-server-atlassian-jira"],
      "env": {
        "ATLASSIAN_SITE_NAME": "${DMSEEK_JIRA_SITE_NAME}",
        "ATLASSIAN_USER_EMAIL": "${DMSEEK_JIRA_EMAIL}",
        "ATLASSIAN_API_TOKEN": "${DMSEEK_JIRA_API_TOKEN}"
      }
    }
  }
}
```

> 实际仓库 `.mcp.json` 当前为空骨架 `{"mcpServers":{}}`，由引导 skill（task #15）按用户探测结果填充上述条目。**配置文件零明文**：凭据全在 OS 环境变量。`.gitignore` 须确保任何含真实凭据的临时脚本/本地 env 文件不被提交；引导 skill 应提醒用户勿提交含真实 token 的设置脚本。

---

## 6. 多仓配置复杂度处理建议（供引导/配置 skill 对接，task #15）

PRD §11.4 风险：仓库多时配置与凭据管理负担上升。建议引导 skill 实现以下能力（本文给契约，skill 任务实现）：

1. **批量探测（非敏感、自动）**：扫描用户指定的若干本地目录，发现 `.git`，读 `git remote get-url origin` 推断 repoSlug，机械生成 server 名 + token 变量名（§2.1）。不读、不要求任何凭据。
2. **凭据引导（敏感、手填）**：逐仓提示「请为 `github-<repoSlug>` 设置 `DMSEEK_GH_TOKEN_<...>`」，输出 §4.3 对应平台命令；token 由用户粘贴到自己的终端执行，skill 不接收、不存储 token 值。
3. **写入配置（路径 B）**：把生成的 server 块写入**共享 `.mcp.json`**（§5）；同时把对应 `mcp__github-<repoSlug>__*` 工具追加到 **repo-tracer 的 `tools` 白名单**（§1.2 独占承重点）；更新 §2.3 映射表。
4. **校验回环**：提供「连通性自检」（提示用户在 Claude Code 内用 `/mcp` 查看各实例连接状态；失败时区分「token 未设/无效」与「网络」）+ 提醒「改了环境变量需重启」。
5. **幂等与增量**：再次运行时，已存在的 server 跳过，仅追加新仓（同步更新对应 `tools` 白名单）；删除仓时提示清理对应变量、`.mcp.json` 条目、`tools` 条目。

**探测/手填界线（已与 team-lead 对齐口径）**：探测仅限非敏感项（仓路径、remote、仓名、平台、shell）；一切凭据（token/邮箱）必须用户手填到自己的环境变量，skill 全程不持有明文。

---

## 7. 对下游任务的契约要点（路径 B）

- **task #8 团队骨架**：核心 MCP 写共享 `.mcp.json`（§5）；**独占靠 `tools` 白名单**——repo-tracer.tools 含 `mcp__github-*`、jira-tracer.tools 含 `mcp__jira__jira_get`（只读）、kb-keeper.tools 含 obsidian/KB 路径、其余 agent.tools 不含任何源类 `mcp__`；所有凭据 `${DMSEEK_*}` 占位；**README/文档诚实声明独占为策略级非物理隔离**。建议骨架期做一次「白名单是否能屏蔽 session 级 MCP 工具」的最小验证（§1.2）。
- **task #12 repo-tracer 实现**：按 §2.3 映射表把 code-analyst 的 repo+模块路由到对应 `mcp__github-<repoSlug>__*`；多仓查询逐实例调用；路由细节与过时判定对齐 T4（`design-source-switching-routing.md`）。
- **task #13 jira-tracer 实现**：仅 `mcp__jira__jira_get`（只读）；按 `design-jira-mcp-toolmap.md` 的 REST v3 端点取数。
- **task #15 引导 skill**：实现 §6 全部能力（写 `.mcp.json` + 同步 repo-tracer.tools）+ §4.3 跨平台命令生成。

---

## 8. 开放点（留待 critic / 实现期确认）

1. ~~Jira MCP 环境变量名~~ **已关闭**：核实为 `ATLASSIAN_SITE_NAME`/`ATLASSIAN_USER_EMAIL`/`ATLASSIAN_API_TOKEN`（见 `design-jira-mcp-toolmap.md`）。
2. **GitHub Copilot 托管 MCP 的 token 授权粒度**：若一个 token 实际按用户/组织授权（可覆盖多仓），则「每仓一 token」可退化为「每仓一命名实例、共用 token」；命名实例分仓仍保留（便于路由），token 变量可合并。**实现期以真实 token 行为校验**（建议 repo-tracer owner 在 task #12 早期验证）。
3. **`tools` 白名单的屏蔽有效性**（路径 B 承重假设，**机制已正面佐证、live 演示待部署环境**）：teammate 未列某 `mcp__` 工具时是否确实无法调用 session 级已加载的该工具——**已由真实 CLI 实测正面佐证**（`--agent` 启动会话工具集 = 精确白名单、`mcp__` 受其管辖，见 §B.3）；**live 端到端负向演示**由 **TC-7.6 运行时**在部署环境补做（归 T16/qa）——机制已佐证 ≠ live 已坐实，不写「已完成 live 坐实/已失败」。**不引入 `deniedMcpServers` 兜底**（用户裁决：会误伤）；纵深防御另由 **L2 声明区块（§1.2.2）+ evidence-verifier** 共同保障独占。
4. 多仓并发连接的 `timeout` / 加载策略，留实现期压测后定。
