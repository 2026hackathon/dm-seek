# 多仓 GitHub MCP 配置形态 + 独占授权 + 凭据环境变量化

> 本文是 MCP 配置形态的**权威契约**：`.mcp.json` 占位、独占授权机制、凭据环境变量化口径、`${VAR}` 命名约定、跨平台设置说明。所有数值/路径/token 一律占位，**绝不出现真实凭据**。

---

## 0. 关键结论（TL;DR）

1. **核心 MCP 写共享 `.mcp.json`**（会话级，所有 teammate 都会连接）。
2. **独占 = 策略级，靠各 agent 定义的 `tools` 白名单实现**：
   - 仅 **repo-tracer** 的 `tools` 含 GitHub MCP 工具（`mcp__dm-github-<repoSlug>__*`，N 个）；
   - 仅 **jira-tracer** 含 Jira MCP 工具（仅 `mcp__jira__jira_get`，只读）；
   - 仅 **kb-keeper** 含 KB/obsidian 读写路径；
   - **dongmei-ma** 及其余 agent 的 `tools` **不含**任何源类 `mcp__` 工具。
3. **每仓一个命名实例**：`dm-github-<repoSlug>`（一个 MCP 服务 ↔ 一个 git repo ↔ 一个独立 token），N 仓即 `.mcp.json` 里 N 个条目。
4. **Jira MCP** 单实例，server 名固定 `jira`；该 server 是**通用 HTTP 透传型**，详见 `design-jira-mcp-toolmap.md`。
5. **凭据硬性环境变量化**：所有 token / URL / 邮箱一律 `${VAR}` 引用，**绝不明文落任何配置文件**。
6. **诚实声明**：「源独占 = L1 工具白名单 + L2 声明区块 + evidence-verifier 兜底」——会话层面 MCP 对全 team 可见，靠白名单 + 声明约束谁能调用。
7. **引导/配置 skill**：探测本地多仓（非敏感）→ 生成 `${VAR}` 命名清单 → 引导用户设置环境变量（敏感项手填）→ 把 server 块写入共享 `.mcp.json` + 把对应 `mcp__` 工具写进 repo-tracer / jira-tracer 的 `tools` 白名单。

---

## 1. 独占授权机制

### 1.1 独占机制：双层边界 + 兜底

| 层 | 机制 | 作用 |
| --- | --- | --- |
| L1 工具白名单（主、承重） | 各 agent `tools` 字段精确列出其可用 `mcp__` 工具（本域）；非授权 agent 不列 | 逐 agent 独占的技术手段（teammate 形态下 `tools` 生效） |
| L2 声明区块（强制规范） | 每个 agent 的 description/system prompt **必须含固定声明区块**（职责范围 / 允许使用的 MCP 服务 / 边界约束硬性），见 §1.2.2 | 行为层强约束 + 跨域走消息/任务列表请求 owner，不直调领域外 MCP |
| 兜底 | evidence-verifier 校验 | 结论出处校验兜底——越域取数/无出处会被校验拦截 |

> **L1 为承重技术防线、L2 为行为规范**。L1 是「正向授权」——靠「只给该给的 agent 列工具」，而非「禁其他 agent」。**不引入 `deniedMcpServers`**（会误伤）。

#### 1.1.2 强制声明区块（每个 agent 必含）

每个 agent 定义除 L1 `tools` 白名单外，**必须在 description/system prompt 加入固定声明区块**：

```
## 职责范围
<负责什么>
## 允许使用的 MCP 服务
<明确列出；无则写「无」>
## 边界约束（硬性）
禁止调用本职责范围外的任何 MCP 服务(mcp__*)。需要跨域数据时，经任务列表/消息向对应 owner agent 请求，绝不直接调用领域外 MCP。
```

各 agent 的「允许使用的 MCP 服务」取值：

| agent | 允许 MCP | 声明区块「允许使用的 MCP 服务」写法 |
| --- | --- | --- |
| repo-tracer | 仅 `mcp__dm-github-<repoSlug>__*`（N 仓） | 列出全部 dm-github-* 系列，注明「不调 jira / 其他 mcp__」 |
| jira-tracer | 仅 `mcp__jira__jira_get`（只读） | 「仅 Jira 只读（jira_get），不写工单、不调 github/其他」 |
| kb-keeper | **无 mcp__**（KB 经 obsidian CLI / Knowlery，非 mcp__ 服务） | 「无 mcp__；KB 经 obsidian CLI / Knowlery；不读源码、不调任何 mcp__ 源服务」 |
| code-analyst | 无（远端取码经 repo-tracer，不直连 MCP） | 「无 mcp__；远端代码经 repo-tracer 取」 |
| dongmei-ma / synthesizer / evidence-verifier | 无 | 「无 mcp__；不直连任何信息源」 |

MCP 在会话层对所有 teammate 加载，但每个 teammate 只能调用其 `tools` 白名单内的 `mcp__` 工具。`tools` 是正向授权，未列即不可调用。skills 放项目级 `.claude/skills/`。

### 1.2 MCP 工具命名规则

引用名：`mcp__<serverName>__<toolName>`，整服务可用 `mcp__<serverName>` 前缀。

- repo-tracer 的 `tools` 含：`mcp__dm-github-<repoSlug>__*`（N 个仓库，逐个或前缀）。
- jira-tracer 的 `tools` 含：`mcp__jira__jira_get`（**仅只读**，不含 post/put/patch/delete，见 `design-jira-mcp-toolmap.md` §1）。
- 其余 agent 的 `tools`：**不出现**任何 `mcp__github-*` / `mcp__jira`。

---

## 2. GitHub MCP — 每仓一命名实例

### 2.1 命名约定

| 元素 | 约定 | 示例 |
| --- | --- | --- |
| server 名 | `dm-github-<repoSlug>` | `dm-github-hdr-delivery-project` |
| `<repoSlug>` | 取 git remote 仓名，小写，非 `[a-z0-9-]` 字符替换为 `-` | `hdr-delivery-project` |
| token 环境变量 | `DMSEEK_GH_TOKEN_<REPO_SLUG_UPPER>` | `DMSEEK_GH_TOKEN_HDR_DELIVERY_PROJECT` |
| 端点 | 固定 `https://api.githubcopilot.com/mcp/`（GitHub Copilot 托管） | — |

> `<REPO_SLUG_UPPER>` = repoSlug 转大写、`-` 转 `_`。命名稳定可由引导 skill 机械生成，便于批量管理。

### 2.2 server 块形态（写入共享 `.mcp.json`）

```jsonc
// .mcp.json（项目根，共享，N 仓 = N 条 github-* 条目）
{
  "mcpServers": {
    "dm-github-hdr-delivery-project": {
      "type": "http",
      "url": "${DMSEEK_GH_MCP_URL:-https://api.githubcopilot.com/mcp/}",
      "headers": {
        "Authorization": "Bearer ${DMSEEK_GH_TOKEN_HDR_DELIVERY_PROJECT}"
      }
    }
    // 第二个仓库（占位，按 §2.1 推导 server 名 + token 变量名）：
    // "dm-github-<repoSlug-2>": {
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
| `D:\dev_repository\hdr-delivery-project` | hdr-delivery-project | `dm-github-hdr-delivery-project` | `DMSEEK_GH_TOKEN_HDR_DELIVERY_PROJECT` |
| …（每仓一行，占位） | … | … | … |

---

## 3. Jira MCP — 单实例（写入共享 `.mcp.json`）

选型：`@aashari/mcp-server-atlassian-jira`（stdio，npx 拉起）。env 变量名见 `design-jira-mcp-toolmap.md` §3。

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

> 核心 MCP（GitHub 多仓 + Jira）都写在此。独占不靠声明位置，靠各 agent `tools` 白名单（§1）。

```jsonc
// .mcp.json（项目根，共享；引导 skill 据探测结果填充）
{
  "mcpServers": {
    // GitHub：每仓一条 github-<repoSlug>（§2.2）
    "dm-github-hdr-delivery-project": {
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

> 实际仓库 `.mcp.json` 由引导 skill 按用户探测结果填充上述条目。**配置文件零明文**：凭据全在 OS 环境变量。

---

## 6. 多仓配置复杂度处理建议（供引导/配置 skill 对接）

仓库多时配置与凭据管理负担上升。建议引导 skill 实现以下能力：

1. **批量探测（非敏感、自动）**：扫描用户指定的若干本地目录，发现 `.git`，读 `git remote get-url origin` 推断 repoSlug，机械生成 server 名 + token 变量名（§2.1）。不读、不要求任何凭据。
2. **凭据引导（敏感、手填）**：逐仓提示「请为 `github-<repoSlug>` 设置 `DMSEEK_GH_TOKEN_<...>`」，输出 §4.3 对应平台命令；token 由用户粘贴到自己的终端执行，skill 不接收、不存储 token 值。
3. **写入配置**：把生成的 server 块写入共享 `.mcp.json`（§5）；同时把对应 `mcp__dm-github-<repoSlug>__*` 工具追加到 repo-tracer 的 `tools` 白名单；更新 §2.3 映射表。
4. **校验回环**：提供「连通性自检」（提示用户在 Claude Code 内用 `/mcp` 查看各实例连接状态；失败时区分「token 未设/无效」与「网络」）+ 提醒「改了环境变量需重启」。
5. **幂等与增量**：再次运行时，已存在的 server 跳过，仅追加新仓（同步更新对应 `tools` 白名单）；删除仓时提示清理对应变量、`.mcp.json` 条目、`tools` 条目。

**探测/手填界线**：探测仅限非敏感项（仓路径、remote、仓名、平台、shell）；一切凭据（token/邮箱）必须用户手填到自己的环境变量，skill 全程不持有明文。

---

## 7. 注意事项

1. **GitHub Copilot 托管 MCP 的 token 授权粒度**：若一个 token 实际按用户/组织授权（可覆盖多仓），则「每仓一 token」可退化为「每仓一命名实例、共用 token」；命名实例分仓仍保留（便于路由），token 变量可合并。
2. 多仓并发连接的 `timeout` / 加载策略，留实现期压测后定。

---

## 8. 官方 Claude Code Plugin 优先 + PAT Fallback 架构（优化期）

> dm-seek 优化期的认证演进策略：逐步从「纯 PAT + 环境变量」迁移到「官方 Claude Code Plugin 优先、PAT 保留 fallback」的双模架构。
>
> **关键区别**：官方 plugin 由 Anthropic / GitHub / Atlassian 官方维护，安装后**自行注册 MCP server**（server 名固定为 `github` / `atlassian`），不需要 dm-seek 自建 OAuth MCP server。`.mcp.json` 中 **不新增 OAuth 条目**——plugin 自行管理 MCP server。dm-seek 仅需在 `tools` 白名单中加入官方 plugin 的 `mcp__` 工具前缀（只读子集），让 repo-tracer / jira-tracer 能调用即可。

### 8.1 官方 Plugin 选型

| 源 | 官方 Plugin | MCP Server 名 | Transport | 认证方式 | 工具前缀 |
|----|-----------|--------------|-----------|---------|---------|
| GitHub | [GitHub Plugin](https://claude.com/plugins/github)（Docker `ghcr.io/github/github-mcp-server`） | `github` | 由 plugin 管理（OAuth 2.1） | Claude Code `/mcp` 命令 → 浏览器 OAuth 授权 | `mcp__github__*` |
| Atlassian | [Atlassian Plugin](https://mcp.atlassian.com/v1/mcp)（Streamable HTTP） | `atlassian` | Streamable HTTP（`/v1/mcp`） | Claude Code `/mcp` 命令 → 浏览器 OAuth 授权 | `mcp__atlassian__*` |

> **安装方式**：用户通过 `/plugin install github` / `/plugin install atlassian` 安装官方 plugin，然后在 `/mcp` 界面完成浏览器 OAuth 授权。token 由 Claude Code keychain 管理，**完全不接触 dm-seek 配置文件**。

### 8.2 双模式架构总览

```
┌──────────────────────────────────────────────────────────┐
│                   setup-guide skill                       │
│  探测仓库 → 提示安装官方 plugin → 写 tools 白名单        │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  ┌─────────────────────────┐  ┌───────────────────────┐  │
│  │  官方 Plugin (OAuth) 优先 │  │  PAT Fallback         │  │
│  │                          │  │                       │  │
│  │ GitHub:                  │  │ GitHub: PAT +         │  │
│  │   server: github         │  │  server: github-<slug>│  │
│  │   tools: mcp__github__*  │  │  tools: mcp__github-  │  │
│  │   安装: /plugin install  │  │         <slug>__*     │  │
│  │         github           │  │  ${DMSEEK_GH_TOKEN_*} │  │
│  │                          │  │                       │  │
│  │ Atlassian (Jira):        │  │ Jira: PAT +           │  │
│  │   server: atlassian      │  │  server: jira         │  │
│  │   tools:                 │  │  tools: mcp__jira__   │  │
│  │     mcp__atlassian__*   │  │         jira_get       │  │
│  │   安装: /plugin install  │  │  ${DMSEEK_JIRA_*}     │  │
│  │         atlassian        │  │                       │  │
│  └─────────────────────────┘  └───────────────────────┘  │
│                                                          │
│  认证: Claude Code keychain (OAuth)                      │
│  凭据: OS 环境变量 (PAT fallback, CI/headless)          │
└──────────────────────────────────────────────────────────┘
```

### 8.3 模式选择矩阵

| 场景 | 推荐模式 | 理由 |
|------|---------|------|
| 交互式用户（桌面 CLI、有浏览器） | **官方 Plugin (OAuth)** | `/plugin install` 后 `/mcp` 一键授权，token 不进配置文件 |
| CI/CD / headless / 无浏览器 | **PAT Fallback** | OAuth 依赖浏览器交互，PAT 环境变量天然适合 CI |
| 非研发用户（PM/测试） | **官方 Plugin (OAuth)** | 无需理解 token/环境变量概念，图形界面点授权即可 |
| 存量用户（已设 PAT） | **PAT Fallback**（保持兼容） | 不强制迁移，已有 PAT 继续工作 |

### 8.4 双模式服务器命名与 tools 白名单

| 源 | 模式 | server 名 | 工具前缀 | dm-seek 操作 | 状态 |
|----|------|----------|---------|-------------|------|
| GitHub | Plugin (OAuth) | `github` | `mcp__github__*` | repo-tracer tools 白名单加入 `mcp__github__*`（只读子集） | **优化期 Phase 1** |
| GitHub | PAT Fallback | `dm-github-<repoSlug>` | `mcp__dm-github-<repoSlug>__*` | repo-tracer tools 白名单加入 `mcp__dm-github-<repoSlug>__*`（现行） | **现行** |
| Atlassian (Jira) | Plugin (OAuth) | `atlassian` | `mcp__atlassian__*` | jira-tracer tools 白名单加入 `mcp__atlassian__*`（只读子集） | **优化期 Phase 2** |
| Jira | PAT Fallback | `jira` | `mcp__jira__jira_get` | jira-tracer tools 白名单加入 `mcp__jira__jira_get`（现行） | **现行** |

> **共存方式**：官方 plugin 自行注册其 MCP server（不经过 `.mcp.json`）；PAT fallback server 仍在 `.mcp.json` 中（§5）。repo-tracer 的 `tools` 白名单同时含 `mcp__github__*`（plugin）+ `mcp__github-<slug>__*`（PAT）；jira-tracer 同时含 `mcp__atlassian__*`（plugin）+ `mcp__jira__jira_get`（PAT）。运行时优先 plugin tools 成功调用则直达，失败时回退 PAT。

### 8.5 对现有机制的兼容性

- **三道防线不变**：Plugin 模式仍受 L1 `tools` 白名单 + L2 声明区块 + evidence-verifier 校验约束。官方 plugin 的 `mcp__` 工具同样受白名单管辖
- **独占归属不变**：远端 GitHub MCP 仅 repo-tracer 含对应 `mcp__github__*` / `mcp__github-<slug>__*` 工具；Jira MCP 仅 jira-tracer 含 `mcp__atlassian__*` / `mcp__jira__jira_get`
- **只读政策不变**：OAuth 仅改变认证，不改变操作权限。**注意**：官方 plugin 暴露的工具包含写操作（如 `create_issue` / `add_comment`），dm-seek 需在 tools 白名单中**精标只读子集**（见 §8.7）
- **setup-guide skill 新增交互**：探测仓库后，提示「建议安装官方 GitHub / Atlassian plugin 并 OAuth 授权」→ 用户 `/plugin install` + `/mcp` 授权 → skill 校验 plugin 连通性 → 更新 agent tools 白名单。PAT 路径保留作为 fallback 选项
- **`.mcp.json` 无需新增 OAuth 条目**：官方 plugin 自行管理 MCP server 注册，不落 `.mcp.json`

### 8.6 安全模型差异

| 维度 | PAT Fallback（现行） | 官方 Plugin OAuth（新增） |
|------|---------------------|--------------------------|
| 凭据存储 | 明文在环境变量（`.zshrc` / 注册表） | Claude Code keychain（加密） |
| token 刷新 | 手动（用户重新创建 PAT → 改环境变量） | Claude Code 自动管理 refresh_token |
| 泄漏风险 | 高（环境变量易被读取/误分享） | 低（keychain 隔离，不落明文） |
| 供应链风险 | 低 | 低（官方 plugin 由 Anthropic / GitHub / Atlassian 维护，非第三方 npm） |
| 权限粒度 | PAT scope（手动配置） | OAuth scope（plugin 声明，`/mcp` 授权时用户确认） |

### 8.7 官方 Plugin 工具的只读子集约束

> **重要**：官方 GitHub / Atlassian plugin 暴露的完整工具集包含写操作（create/update/delete/transition/comment 等）。dm-seek 是只读溯源系统，必须在 agent `tools` 白名单中**精标只读子集**——不授予任何写工具。

**GitHub plugin 只读子集**（`mcp__github__` 前缀）：
- `search_code` / `get_file_contents`（取码）
- `get_commit` / `list_commits` / `compare_commits`（取提交历史）
- `search_repositories` / `get_repository`（仓库信息）
- ~~`create_issue` / `create_pr` / `commit_files` / `delete_files`~~（全部排除）

**Atlassian plugin 只读子集**（`mcp__atlassian__` 前缀）：
- `searchJiraIssuesUsingJql` / `getVisibleJiraProjects` / `getJiraProjectIssueTypesMetadata`（取工单与项目）
- `getTransitionsForJiraIssue` / `getJiraIssueRemoteIssueLinks`（取工单元数据）
- `getAccessibleAtlassianResources`（资源清单）
- ~~`addCommentToJiraIssue` / `addWorklogToJiraIssue` / `createFooterComment`~~（全部排除）

> 具体工具名以官方 plugin 实际注册为准，优化期实施时逐工具核对后放入白名单。工具名格式 `mcp__github__<toolName>` / `mcp__atlassian__<toolName>`（双下划线 `__` 分隔）。

---

## 9. 注意事项（续）

1. **官方 GitHub plugin 与 PAT 方案的仓库粒度差异**：官方 `github` plugin 是一个统一 MCP server（覆盖用户有权限的全部仓库），而非 PAT 方案的「每仓一实例」。repo-tracer 的路由逻辑需处理此差异——plugin 模式下不需要按 repoSlug 路由到不同 server，而是统一经 `mcp__github__*` 工具、用 repo 参数区分仓库。
2. **Atlassian plugin 覆盖范围超出 Jira**：官方 Atlassian plugin 同时覆盖 Jira + Confluence + Compass。dm-seek 仅需 Jira 相关工具（取工单业务原因），Confluence/Compass 工具不列入白名单。jira-tracer 的只读子集需精确到 Jira scope。
3. 多仓并发连接的 `timeout` / 加载策略，留实现期压测后定。
