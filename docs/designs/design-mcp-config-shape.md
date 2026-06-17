# dm-seek MCP 配置形态 + 独占授权

> 本文是 MCP 配置形态的**权威契约**：MCP server 选型、独占授权机制、`tools` 白名单。凭据零明文。

---

## 0. 关键结论（TL;DR）

1. **MCP server 选型**：
   - **GitHub（路径 A，推荐）**：`gh` CLI 扩展 `shuymn/gh-mcp`（`gh auth login` 浏览器 OAuth，零 PAT）
   - **GitHub（路径 B，备选）**：官方 GitHub MCP（`https://api.githubcopilot.com/mcp`，`${GITHUB_TOKEN}` PAT）
   - **Jira**：Atlassian Plugin（`/plugin install atlassian@claude-plugins-official` → `/mcp` OAuth 授权）
2. **独占 = 策略级，靠各 agent 定义的 `tools` 白名单实现**：
   - 仅 **repo-tracer** 的 `tools` 含 GitHub MCP 工具（`mcp__github__*`，只读子集）；
   - 仅 **jira-tracer** 的 `tools` 含 Atlassian MCP 工具（`mcp__atlassian__*`，只读子集）；
   - 仅 **kb-keeper** 含 KB/obsidian 读写路径；
   - **dongmei-ma** 及其余 agent 的 `tools` **不含**任何源类 `mcp__` 工具。
3. **凭据零明文**：
   - GitHub 路径 A：`gh` CLI keyring 管理 OAuth token，零配置文件
   - GitHub 路径 B：`${GITHUB_TOKEN}` PAT 环境变量，`.mcp.json` 仅含变量占位
   - Jira：Claude Code keychain（OAuth）
4. **诚实声明**：「源独占 = L1 工具白名单 + L2 声明区块 + evidence-verifier 兜底」——MCP server 在会话层对全 team 可见，靠白名单 + 声明约束谁能调用。

---

## 1. 独占授权机制

### 1.1 独占机制：双层边界 + 兜底

| 层 | 机制 | 作用 |
| --- | --- | --- |
| L1 工具白名单（主、承重） | 各 agent `tools` 字段精确列出其可用 `mcp__` 工具（本域）；非授权 agent 不列 | 逐 agent 独占的技术手段（teammate 形态下 `tools` 生效） |
| L2 声明区块（强制规范） | 每个 agent 的 description/system prompt **必须含固定声明区块**（职责范围 / 允许使用的 MCP 服务 / 边界约束硬性） | 行为层强约束 + 跨域走消息/任务列表请求 owner，不直调领域外 MCP |
| 兜底 | evidence-verifier 校验 | 结论出处校验兜底——越域取数/无出处会被校验拦截 |

> **L1 为承重技术防线、L2 为行为规范**。不引入 `deniedMcpServers`（会误伤）。

### 1.2 强制声明区块

每个 agent 定义除 L1 `tools` 白名单外，**必须在 description/system prompt 加入固定声明区块**：

```
## 职责范围
<负责什么>
## 允许使用的 MCP 服务
<明确列出；无则写「无」>
## 边界约束（硬性）
禁止调用本职责范围外的任何 MCP 服务(mcp__*)。需要跨域数据时，经任务列表/消息向对应 owner agent 请求。
```

各 agent 取值：

| agent | 允许 MCP | 声明写法 |
| --- | --- | --- |
| repo-tracer | `mcp__github__*`（官方 GitHub MCP，只读子集） | 「仅 GitHub MCP 只读子集，不调 atlassian/其他 mcp__」 |
| jira-tracer | `mcp__atlassian__*`（Atlassian Plugin，只读子集） | 「仅 Atlassian Plugin 只读子集，不写工单、不调 github/其他」 |
| kb-keeper | **无 mcp__**（KB 经 obsidian CLI / Knowlery） | 「无 mcp__；KB 经 obsidian CLI / Knowlery」 |
| code-analyst | 无（远端取码经 repo-tracer） | 「无 mcp__；远端代码经 repo-tracer 取」 |
| dongmei-ma / synthesizer / evidence-verifier | 无 | 「无 mcp__」 |

skills 放项目级 `.claude/skills/`。

### 1.3 MCP 工具命名规则

引用名：`mcp__<serverName>__<toolName>`，整服务可用 `mcp__<serverName>` 前缀。

- repo-tracer 的 `tools` 含：`mcp__github__*`（官方 GitHub MCP，只读子集）
- jira-tracer 的 `tools` 含：`mcp__atlassian__*`（Atlassian Plugin，只读子集）
- 其余 agent 的 `tools`：**不出现**任何 `mcp__github*` / `mcp__atlassian*`

---

## 2. MCP Server 架构

### 2.1 选型

| 源 | MCP Server | Server 名 | 运行方式 | 认证方式 | 工具前缀 |
|----|-----------|--------------|---------|---------|---------|
| GitHub（路径 A） | `gh` CLI + `shuymn/gh-mcp` | `github` | `command: gh` + `args: [mcp]` | `gh auth login` OAuth（keyring） | `mcp__github__*` |
| GitHub（路径 B） | 官方 GitHub MCP | `github` | `type: http`（`.mcp.json`） | `GITHUB_TOKEN` PAT（Bearer） | `mcp__github__*` |
| Atlassian | Atlassian Plugin | `atlassian` | Plugin 注册（Streamable HTTP） | `/mcp` OAuth 授权 | `mcp__atlassian__*` |

### 2.2 架构总览

```
┌─────────────────────────────────────────────────────────────────┐
│                     setup-guide skill                             │
│  路径 A：gh auth login → gh extension install → 校验连通性      │
│  路径 B：创建 PAT → 设 GITHUB_TOKEN → 校验连通性                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  GitHub:                           Atlassian (Jira):            │
│    server: github                    server: atlassian           │
│    tools: mcp__github__*             tools: mcp__atlassian__*     │
│    路径 A: command: gh mcp            安装: /plugin install       │
│    路径 B: type: http                  atlassian                  │
│           url: api.githubcopilot.com/mcp  认证: /mcp OAuth       │
│    路径 A 认证: gh OAuth (keyring)                              │
│    路径 B 认证: PAT (GITHUB_TOKEN)                              │
│                                                                 │
│  凭据: 零明文——OAuth 仅 keyring/Keychain，PAT 仅环境变量        │
└─────────────────────────────────────────────────────────────────┘
```

### 2.3 安全模型

| 维度 | GitHub 路径 A（OAuth） | GitHub 路径 B（PAT） | Jira（OAuth） |
|------|----------------------|---------------------|---------------|
| 凭据存储 | `gh` CLI keyring | 环境变量 | Claude Code keychain |
| 凭据明文 | 零 | 零——`.mcp.json` 不写 token | 零 |
| 泄漏风险 | 低（keyring 隔离） | 中（环境变量） | 低（keychain 隔离） |
| 供应链风险 | 低（官方 github-mcp-server 内嵌） | 低（GitHub 官方维护） | 低（Atlassian 官方维护） |

### 2.4 只读子集约束

GitHub（`mcp__github__`）：`search_code`、`get_file_contents`、`get_commit`、`list_commits`、`search_repositories`、`list_branches`、`search_issues`、`get_issue`、`list_issues`、`search_pull_requests`、`get_pull_request`、`list_pull_requests`、`search_users`、`get_authenticated_user`
排除：`create_*`、`delete_*`、`commit_*`、`push_*`、`merge_*` 等写工具

Jira（`mcp__atlassian__`）：`searchJiraIssuesUsingJql`、`getVisibleJiraProjects` 等只读子集
排除：`addCommentToJiraIssue`、`addWorklogToJiraIssue` 等写工具

---

## 3. 注意事项

1. **GitHub 仓库覆盖**：官方 MCP 统一覆盖用户有权限的全部仓库。repo-tracer 经 `mcp__github__*` 工具、用 repo 参数区分仓库
2. **Org repo**：PAT 需在 GitHub token 页面点击 Configure SSO 授权对应 org
3. **工具名格式**：`mcp__<server>__<toolName>`（双下划线 `__` 分隔）
