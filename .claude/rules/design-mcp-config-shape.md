# dm-seek MCP 配置形态 + 独占授权（纯 Plugin）

> 本文是 MCP 配置形态的**权威契约**：官方 Plugin 按需安装、独占授权机制、`tools` 白名单。MCP server 由官方 plugin 自行注册，**不落 `.mcp.json`**。无凭据明文。

---

## 0. 关键结论（TL;DR）

1. **MCP server 由官方 Claude Code plugin 自行注册**：GitHub Plugin（server `github`）+ Atlassian Plugin（server `atlassian`）。不落 `.mcp.json`，用户无需手动配置环境变量。
2. **独占 = 策略级，靠各 agent 定义的 `tools` 白名单实现**：
   - 仅 **repo-tracer** 的 `tools` 含 GitHub MCP 工具（`mcp__github__*`，只读子集）；
   - 仅 **jira-tracer** 的 `tools` 含 Atlassian MCP 工具（`mcp__atlassian__*`，只读子集）；
   - 仅 **kb-keeper** 含 KB/obsidian 读写路径；
   - **dongmei-ma** 及其余 agent 的 `tools` **不含**任何源类 `mcp__` 工具。
3. **官方 Plugin 选型**：
   - **GitHub**：[GitHub Plugin](https://claude.com/plugins/github) — server `github`，`/plugin install github` → `/mcp` 浏览器 OAuth 授权
   - **Atlassian**：[Atlassian Plugin](https://mcp.atlassian.com/v1/mcp) — server `atlassian`，`/plugin install atlassian` → `/mcp` 浏览器 OAuth 授权
4. **凭据由 Claude Code keychain 管理**（OAuth），**零明文、零环境变量**。
5. **诚实声明**：「源独占 = L1 工具白名单 + L2 声明区块 + evidence-verifier 兜底」——官方 plugin 的 MCP server 在会话层对全 team 可见，靠白名单 + 声明约束谁能调用。
6. **setup-guide skill**：探测本地多仓 → 提示安装官方 plugin → 校验 plugin 连通性 → 更新 agent `tools` 白名单（只读子集）。无需引导设置环境变量或手填 token。

---

## 1. 独占授权机制

### 1.1 独占机制：双层边界 + 兜底

| 层 | 机制 | 作用 |
| --- | --- | --- |
| L1 工具白名单（主、承重） | 各 agent `tools` 字段精确列出其可用 `mcp__` 工具（本域）；非授权 agent 不列 | 逐 agent 独占的技术手段（teammate 形态下 `tools` 生效） |
| L2 声明区块（强制规范） | 每个 agent 的 description/system prompt **必须含固定声明区块**（职责范围 / 允许使用的 MCP 服务 / 边界约束硬性），见 §1.1.2 | 行为层强约束 + 跨域走消息/任务列表请求 owner，不直调领域外 MCP |
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
| repo-tracer | `mcp__github__*`（官方 GitHub plugin，只读子集） | 「仅 GitHub plugin 只读子集（取码/取提交历史），不调 atlassian/其他 mcp__」 |
| jira-tracer | `mcp__atlassian__*`（官方 Atlassian plugin，只读子集，仅 Jira get/search） | 「仅 Atlassian plugin 只读子集（Jira get/search），不写工单、不调 github/其他」 |
| kb-keeper | **无 mcp__**（KB 经 obsidian CLI / Knowlery，非 mcp__ 服务） | 「无 mcp__；KB 经 obsidian CLI / Knowlery；不读源码、不调任何 mcp__ 源服务」 |
| code-analyst | 无（远端取码经 repo-tracer，不直连 MCP） | 「无 mcp__；远端代码经 repo-tracer 取」 |
| dongmei-ma / synthesizer / evidence-verifier | 无 | 「无 mcp__；不直连任何信息源」 |

MCP 在会话层对所有 teammate 加载，但每个 teammate 只能调用其 `tools` 白名单内的 `mcp__` 工具。`tools` 是正向授权，未列即不可调用。skills 放项目级 `.claude/skills/`。

### 1.2 MCP 工具命名规则

引用名：`mcp__<serverName>__<toolName>`，整服务可用 `mcp__<serverName>` 前缀。

- repo-tracer 的 `tools` 含：`mcp__github__*`（官方 GitHub plugin，只读子集——仅 get/search 工具，不授予 create/commit/delete 写工具）。
- jira-tracer 的 `tools` 含：`mcp__atlassian__*`（官方 Atlassian plugin，只读子集——仅 Jira get/search 工具，不授予 create/update/transition/comment 写工具）。
- 其余 agent 的 `tools`：**不出现**任何 `mcp__github*` / `mcp__atlassian*`。

---

## 2. 官方 Plugin 架构

> dm-seek 的 MCP 认证方案：**纯官方 Claude Code Plugin**。由 Anthropic / GitHub / Atlassian 官方维护，安装后自行注册 MCP server，token 由 Claude Code keychain 管理。
>
> `.mcp.json` **不需要 MCP server 条目**——官方 plugin 自行注册。dm-seek 仅需在 `tools` 白名单中加入官方 plugin 的 `mcp__` 工具前缀（只读子集）。

### 2.1 官方 Plugin 选型

| 源 | 官方 Plugin | MCP Server 名 | Transport | 认证方式 | 工具前缀 |
|----|-----------|--------------|-----------|---------|---------|
| GitHub | [GitHub Plugin](https://claude.com/plugins/github)（Docker `ghcr.io/github/github-mcp-server`） | `github` | 由 plugin 管理（OAuth 2.1） | Claude Code `/mcp` 命令 → 浏览器 OAuth 授权 | `mcp__github__*` |
| Atlassian | [Atlassian Plugin](https://mcp.atlassian.com/v1/mcp)（Streamable HTTP） | `atlassian` | Streamable HTTP（`/v1/mcp`） | Claude Code `/mcp` 命令 → 浏览器 OAuth 授权 | `mcp__atlassian__*` |

> **安装方式**：用户通过 `/plugin install github` / `/plugin install atlassian` 安装官方 plugin，然后在 `/mcp` 界面完成浏览器 OAuth 授权。token 由 Claude Code keychain 管理，**完全不接触 dm-seek 配置文件**。

### 2.2 架构总览

```
┌──────────────────────────────────────────────────────────┐
│                   setup-guide skill                       │
│  探测仓库 → 提示安装官方 plugin → 写 tools 白名单        │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  官方 Claude Code Plugin (OAuth)                         │
│                                                          │
│  GitHub:                      Atlassian (Jira):          │
│    server: github               server: atlassian        │
│    tools: mcp__github__*        tools: mcp__atlassian__* │
│    安装: /plugin install         安装: /plugin install   │
│          github                        atlassian         │
│    授权: /mcp OAuth               授权: /mcp OAuth       │
│                                                          │
│  认证: Claude Code keychain (OAuth)                      │
│  凭据: 零明文、零环境变量                                │
└──────────────────────────────────────────────────────────┘
```

### 2.3 模式选择矩阵

| 场景 | 推荐 | 理由 |
|------|------|------|
| 交互式用户（桌面 CLI、有浏览器） | **官方 Plugin (OAuth)** | `/plugin install` 后 `/mcp` 一键授权，token 不进配置文件 |
| 非研发用户（PM/测试） | **官方 Plugin (OAuth)** | 无需理解 token/环境变量概念，图形界面点授权即可 |
| CI/CD / headless / 无浏览器 | **额外配置方式** | 官方 plugin 需要浏览器交互 OAuth；headless 环境需参考官方 plugin CI 文档 |

### 2.4 服务器命名与 tools 白名单

| 源 | server 名 | 工具前缀 | dm-seek 操作 |
|----|----------|---------|-------------|
| GitHub | `github` | `mcp__github__*` | repo-tracer tools 白名单加入 `mcp__github__*`（只读子集——仅 get/search，不授予 create/commit/delete） |
| Atlassian (Jira) | `atlassian` | `mcp__atlassian__*` | jira-tracer tools 白名单加入 `mcp__atlassian__*`（只读子集——仅 Jira get/search，不授予 create/update/transition/comment） |

> 官方 plugin 自行注册其 MCP server（不经过 `.mcp.json`）。运行时 repo-tracer 经 `mcp__github__*` 工具调用（用 repo 参数区分仓库），jira-tracer 经 `mcp__atlassian__*` 工具调用。

### 2.5 对现有机制的兼容性

- **三道防线不变**：Plugin 模式受 L1 `tools` 白名单 + L2 声明区块 + evidence-verifier 校验约束。官方 plugin 的 `mcp__` 工具同样受白名单管辖
- **独占归属不变**：远端 GitHub MCP 仅 repo-tracer 含 `mcp__github__*` 工具；Jira MCP 仅 jira-tracer 含 `mcp__atlassian__*` 工具
- **只读政策不变**：OAuth 仅改变认证，不改变操作权限。dm-seek 在 agent `tools` 白名单中**精标只读子集**（见 §2.7）
- **setup-guide skill 流程**：探测仓库后，提示「请安装官方 GitHub / Atlassian plugin 并 OAuth 授权」→ 用户 `/plugin install` + `/mcp` 授权 → skill 校验 plugin 连通性 → 更新 agent tools 白名单
- **`.mcp.json` 无需 MCP server 条目**：官方 plugin 自行管理 MCP server 注册，不落 `.mcp.json`

### 2.6 安全模型

| 维度 | 说明 |
|------|------|
| 凭据存储 | Claude Code keychain（加密） |
| token 刷新 | Claude Code 自动管理 refresh_token |
| 泄漏风险 | 低（keychain 隔离，不落明文配置文件或环境变量） |
| 供应链风险 | 低（官方 plugin 由 Anthropic / GitHub / Atlassian 维护，非第三方 npm） |
| 权限粒度 | OAuth scope（plugin 声明，`/mcp` 授权时用户确认） |

### 2.7 官方 Plugin 工具的只读子集约束

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

> 具体工具名以官方 plugin 实际注册为准，实施时逐工具核对后放入白名单。工具名格式 `mcp__github__<toolName>` / `mcp__atlassian__<toolName>`（双下划线 `__` 分隔）。

---

## 3. 注意事项

1. **官方 GitHub plugin 的仓库覆盖**：官方 `github` plugin 是一个统一 MCP server（覆盖用户有权限的全部仓库）。repo-tracer 不需要按 repoSlug 路由到不同 server，而是统一经 `mcp__github__*` 工具、用 repo 参数区分仓库。
2. **Atlassian plugin 覆盖范围超出 Jira**：官方 Atlassian plugin 同时覆盖 Jira + Confluence + Compass。dm-seek 仅需 Jira 相关工具（取工单业务原因），Confluence/Compass 工具不列入白名单。jira-tracer 的只读子集需精确到 Jira scope。
3. **官方 plugin 的 `mcp__` 工具名前缀以实际注册为准**——双下划线 `__` 分隔 server 名与 toolName（`mcp__github__<toolName>` / `mcp__atlassian__<toolName>`）。
4. 多仓并发连接的 `timeout` / 加载策略，留实施时压测后定。
