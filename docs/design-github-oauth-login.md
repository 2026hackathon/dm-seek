# GitHub OAuth 登录方案设计

> 版本：v1.2 | 日期：2026-06-16 | 作者：architect-3 | 审查：critic-2 round-1 + team-lead v1.2
>
> 关联文档：`design-mcp-config-shape.md`、`runtime-spec.md`、`design-source-switching-routing.md`
>
> **v1.2 变更**：彻底移除 `gh` CLI 依赖（team-lead 决策）；dm-seek 的 OAuth 和 PAT 路径均不依赖 `gh` CLI；setup-guide 不再检测/安装 `gh` CLI
>
> **v1.1 变更**：修正官方 Plugin 认证机制描述（与 `gh` CLI 无关，见 §1.2.4）；补充两条路径工具名映射表（§4.4）；修正 Windows PAT 环境变量设置引导防终端历史泄漏（§8.2）；补充 `.mcp.json` 四种场景行为矩阵（§4.2.1）；补充 OAuth 失效检测与恢复流程（§2.3.3）；rate limit 应对区分 OAuth vs PAT（§9.1.4）；`design-mcp-config-shape.md` 零环境变量分路径标注（§5.3）；待定项预期解决窗口（§9.3）

## 1. 背景与目标

### 1.1 当前状态

dm-seek 的 GitHub 远端访问当前依赖两条路径：

- **官方 GitHub Plugin 路径**（`github@claude-plugins-official`）：用户通过 `/plugin install github` 安装官方 Plugin，然后在 `/mcp` 界面完成浏览器 OAuth 授权。Plugin 自管 OAuth 流程（`/mcp` → Authenticate → 浏览器跳转 GitHub → 用户授权 → callback → token 入 Claude Code keychain），与 `gh` CLI 无关。这是当前 `design-mcp-config-shape.md` 规定的官方 Plugin 架构。
- **手动 PAT 配置**：用户自行在 GitHub Settings 创建 Personal Access Token，设置为环境变量 `DMSEEK_GH_TOKEN_<REPO_SLUG_UPPER>`，通过 `.mcp.json` 配置 GitHub Copilot 托管 MCP（`https://api.githubcopilot.com/mcp/`）。这是 PRD 中原定的 MCP 配置方案。

> **关键澄清**（critic A1 / team-lead v1.2）：官方 GitHub Plugin 在 `/mcp` 界面直接完成 OAuth 授权，token 存入 Claude Code keychain。dm-seek 不依赖 `gh` CLI——OAuth 和 PAT 两条路径均不需要。旧 setup-guide 中的 `gh auth login` 步骤已在 v1.2 彻底移除。

### 1.2 现状问题

1. **旧 setup-guide 绕道 `gh` CLI 增加了不必要的间接依赖**：当前 setup-guide（`.claude/skills/setup-guide/SKILL.md`）把 `gh auth login` 作为认证步骤，导致用户误以为 `gh` CLI 是必需的。dm-seek 的 OAuth 和 PAT 两条路径本身均不依赖 `gh` CLI——官方 Plugin 在 `/mcp` 界面直接完成 OAuth，PAT 路径仅需环境变量。旧 setup-guide 中的 `gh` CLI 检测/安装/登录步骤是历史迂回，v1.2 已彻底移除。

2. **PAT 路径体验门槛高**：用户需要自行打开 GitHub Settings > Developer settings > Personal access tokens，创建 token、选择 scope、复制粘贴。对于非研发用户（PM、测试），这个流程是显著的认知负担，是 dm-seek "为非研发用户降低溯源门槛"目标的实现障碍。

3. **headless/CI 场景缺少明确路径**：官方 Plugin 的 `/mcp` OAuth 需要浏览器交互，PAT 手动创建也需要浏览器（在另一台机器上完成后再搬运 token）。CI/CD、远程 SSH、无图形界面的服务器等场景缺乏开箱即用的方案。

4. **官方 Plugin OAuth 认证路径正确但 setup-guide 引导偏航**：官方 Plugin 在 `/mcp` 界面自行完成 OAuth，与 `gh` CLI 完全无关。但 setup-guide 的旧引导流程（`gh detect → install gh → gh auth login → install plugin`）把 `gh` CLI 放在关键路径上，导致用户误以为 `gh` CLI 是前置依赖。v1.2 修正引导路径为：`/plugin install github → /mcp Authenticate`，移除所有 `gh` CLI 步骤。

### 1.3 设计目标

1. **确立官方 Plugin OAuth 为唯一主路径**：官方 GitHub Plugin 在 `/mcp` 界面直接完成 OAuth，setup-guide 引导 `/plugin install github → /mcp Authenticate`，两步完成。dm-seek 不依赖 `gh` CLI。
2. **保留 PAT 手动配置作为回退路径**：headless/CI 场景、企业网络限制浏览器跳转的场景，用户仍可使用环境变量 `DMSEEK_GH_TOKEN_<REPO_SLUG_UPPER>` 配置 PAT。
3. **setup-guide 提供双轨选择**：首次引导时根据场景（有无浏览器、是否 headless）给出推荐路径，每一步提供跳过/回退出口。

## 2. OAuth 2.0 授权码流程设计

### 2.1 整体流程

```
用户端                                  GitHub                    Claude Code
  │                                      │                          │
  │  1. /plugin install github           │                          │
  │─────────────────────────────────────────────────────────────────│
  │                                      │                          │
  │  2. /mcp → 选择 github → Authenticate│                          │
  │─────────────────────────────────────────────────────────────────│
  │                                      │                          │
  │  3. 浏览器打开                        │                          │
  │     https://github.com/login/        │                          │
  │     oauth/authorize?                │                          │
  │     client_id=...&                  │                          │
  │     redirect_uri=...&               │                          │
  │     scope=repo,read:org             │                          │
  │─────────────────────────────────────│                          │
  │                                      │                          │
  │  4. 用户登录 GitHub / 确认授权        │                          │
  │─────────────────────────────────────│                          │
  │                                      │                          │
  │  5. 302 redirect → localhost callback│                          │
  │     ?code=xxxx                       │                          │
  │<────────────────────────────────────│                          │
  │                                      │                          │
  │  6.                                  │  POST /login/oauth/      │
  │                                      │  access_token            │
  │                                      │  code + client_secret    │
  │                                      │<─────────────────────────│
  │                                      │                          │
  │  7.                                  │  {access_token, ...}     │
  │                                      │─────────────────────────│
  │                                      │                          │
  │  8. token 存入 Claude Code keychain  │                          │
  │     （加密存储，零明文）              │                          │
  │─────────────────────────────────────────────────────────────────│
  │                                      │                          │
  │  9. repo-tracer 自检：               │                          │
  │     mcp__github__get_file_contents ✅│                          │
```

**关键步骤说明**：

- **步骤 1-2**：用户通过 Claude Code 的 `/plugin install` 和 `/mcp` 界面触发认证，不需要手动注册 OAuth App。官方 GitHub Plugin 自带 `client_id`，用户无需自行获取。
- **步骤 3-5**：Claude Code（或官方 plugin）启动本地 HTTP 服务器监听 `localhost` 回调，打开浏览器跳转 GitHub 授权页。用户完成 GitHub 登录和授权确认。
- **步骤 6-7**：Claude Code 用回调收到的 `code` 向 GitHub 交换 `access_token`。这个交换需要 `client_secret`——由官方 plugin 内置（不暴露给用户），或通过 plugin 的后端代理完成（OAuth 2.1 推荐的 BFF 模式）。
- **步骤 8**：token 存入 Claude Code keychain（操作系统级加密存储），零明文落 `.mcp.json`。

### 2.2 OAuth App 注册

#### 2.2.1 方案选择：官方 Plugin 内置 vs 用户自行注册

| 方案 | 优点 | 缺点 | 推荐 |
|------|------|------|------|
| **A: 官方 Plugin 内置** | 用户零配置；`client_secret` 不暴露 | 依赖官方 plugin 更新；scope 固定 | **首选**（当前 `github@claude-plugins-official` 已支持） |
| **B: 用户自行注册 GitHub OAuth App** | 自主控制 scope；可自定义 redirect_uri | 用户需理解 OAuth 概念；`client_secret` 管理负担 | 回退方案（官方 plugin 不可用时） |

**设计决策**：dm-seek 采用方案 A（官方 GitHub Plugin 内置 OAuth）。官方 `github@claude-plugins-official` 的认证流程是：`/plugin install github` 安装 → `/mcp` 界面选择 github → Authenticate → 浏览器跳转 GitHub OAuth 授权页 → 用户授权 → token 存入 Claude Code keychain。整个过程与 `gh` CLI 无任何依赖关系。dm-seek 不引入 `gh` CLI 作为认证方式。

#### 2.2.2 OAuth App 参数（方案 B 参考）

若用户需要在无官方 plugin 环境下自行注册 OAuth App：

| 参数 | 取值 | 说明 |
|------|------|------|
| **Application name** | `dm-seek-<user>` | 用户自行命名 |
| **Homepage URL** | `https://github.com` | 或用户自定义 |
| **Authorization callback URL** | `http://localhost:18765/callback` | localhost 回调（端口见 §2.2.3） |
| **Client ID** | 注册后 GitHub 自动生成 | 公开，可落配置文件 |
| **Client Secret** | 注册后 GitHub 自动生成 | 保密，**只能通过环境变量注入，严禁明文落盘** |

#### 2.2.3 Redirect URI 方案

**推荐 localhost 回调**：

- URI 格式：`http://localhost:<port>/callback`
- 端口选择：建议使用固定端口 `18765`（Claude Code 默认 OAuth 回调端口），备选端口 `18766`、`18767`（冲突时递增尝试）。
- 理由：
  - localhost 回调是 OAuth 2.0 for Native Apps（RFC 8252）推荐方案。
  - 不需要公网域名或 HTTPS 证书。
  - loopback 接口不受外部网络攻击。
  - 官方 GitHub Plugin 已采用此方案，dm-seek 直接复用。

**备选方案**：Custom URI scheme（`claude://oauth-callback`）——部分平台（如 VS Code 扩展）采用。dm-seek 不引入此方案以减少复杂度，统一用 localhost。

#### 2.2.4 需要的 Scopes（最小权限原则）

| Scope | 用途 | 必要性 |
|-------|------|--------|
| `repo` | 读取私有仓库代码、commit 历史 | **必须**——dm-seek 溯源需要访问仓库内容 |
| `read:org` | 读取组织成员信息（非必须但有助于识别提交者上下文） | 可选 |
| `user:email` | 读用户邮箱（GitHub 用户身份识别） | 可选 |

> **不申请的 scope**：`write:org`、`delete_repo`、`admin:org`、`workflow` 等写权限。dm-seek 是只读系统，OAuth scope 也只申请只读权限，从授权层面巩固只读安全。

### 2.3 Token 交换与管理

#### 2.3.1 Authorization Code → Access Token 交换

```
POST https://github.com/login/oauth/access_token
Content-Type: application/json
Accept: application/json

{
  "client_id": "Iv1.xxxx",
  "client_secret": "xxxx",       // 官方 plugin 后端代理，不暴露给用户
  "code": "xxxx",                // 回调 URL 携带的临时 code
  "redirect_uri": "http://localhost:18765/callback"
}
```

响应：

```json
{
  "access_token": "gho_xxxx",
  "token_type": "bearer",
  "scope": "repo,read:org"
}
```

- **GitHub OAuth access token 不过期**（除非用户主动撤销或 token 长时间未使用被 GitHub 自动清理）。因此 dm-seek 不需要实现 token 刷新逻辑。
- **撤销处理**：若 token 被撤销，Claude Code 会检测到 API 调用失败（401），提示用户重新授权。此时用户在 `/mcp` 界面重新点击 Authenticate 即可。

#### 2.3.2 Token 存储方案

- **存储位置**：Claude Code keychain（操作系统级加密存储——Windows Credential Manager / macOS Keychain / Linux Secret Service）。
- **零明文原则**：token 不写入 `.mcp.json`、不写入环境变量、不写入任何项目文件。
- **与其他凭据的隔离**：每个 OAuth token 独立存储，互不影响。GitHub OAuth token 和 Jira OAuth token 各自存放在 keychain 的不同条目中。

#### 2.3.3 Token 失效检测与恢复

**失效检测时机**（两个检测点）：

| 检测点 | 触发条件 | 检测方式 | 执行者 |
|--------|---------|---------|--------|
| **启动自检** | 每次 agent 启动 | 调用 `mcp__github__get_authenticated_user` 验证连通性，401/403 即为失效 | repo-tracer（自检 §0） |
| **运行时首次调用** | 溯源链路首次使用 `mcp__github__*` 工具 | 工具调用返回 401 即为失效 | repo-tracer（运行时） |

**失效场景**：

1. 用户在 GitHub Settings > Applications 中主动撤销授权。
2. Token 超过 1 年未使用，GitHub 可能自动回收。
3. 用户更换 GitHub 账号。
4. 官方 Plugin 被卸载后重新安装（token 可能丢失）。

**中断查询恢复流程**：

```
运行时 401 → repo-tracer 检测到 OAuth token 失效
    │
    ├─ 1. repo-tracer 停止当前溯源，标记 repo_timeline 中受影响仓库为 unconfigured
    │      （区分"token 失效"与"仓库不存在"——前者是所有仓库调用都失败，后者是单仓）
    │
    ├─ 2. repo-tracer 通知 dongmei-ma：
    │      "GitHub OAuth token 已失效，当前查询 [queryId] 的远端取码/远端历史缺失。
    │       请用户重新在 /mcp 界面完成 GitHub Authenticate，然后重试本查询。"
    │
    ├─ 3. dongmei-ma 向用户报告：
    │      "GitHub 授权已失效——请在 Claude Code 中打开 /mcp 面板，
    │       选择 github → Authenticate，浏览器完成授权后回复"已授权"继续本次查询。"
    │
    └─ 4. 用户完成重新授权回复后，dongmei-ma 重新派发该轮溯源
           （不递增 round——token 失效不算发散返工，是外部依赖恢复）
```

**GitHub OAuth access token 默认不过期**（与传统 OAuth 2.0 的 1 小时过期不同，GitHub 的实现是长期有效的），因此 dm-seek 不需要实现传统 OAuth 的 refresh_token 轮换逻辑。

## 3. OAuth vs PAT 双轨架构

### 3.1 对比表

| 维度 | OAuth 路径（官方 Plugin） | PAT 路径 |
|------|--------------------------|----------|
| 认证方式 | Claude Code `/mcp` 界面 → 浏览器跳转 GitHub 授权 | 用户在 GitHub Settings 手动创建 Personal Access Token |
| 适用场景 | 交互式桌面环境（有浏览器） | headless / CI / 无浏览器 / 远程 SSH |
| 凭据存储 | Claude Code keychain（操作系统级加密） | 环境变量 `DMSEEK_GH_TOKEN_<REPO_SLUG_UPPER>` |
| 凭据生命周期 | 长期有效，撤销后需重新授权 | 用户手动管理（创建/撤销/轮换） |
| 配置复杂度 | 低——`/plugin install github` + `/mcp` 点击授权，两步完成 | 中——打开 GitHub Settings → 创建 Token → 选 scope → 复制 → 设环境变量 |
| Scope 控制 | 由官方 Plugin 预定义（`repo`, `read:org` 等） | 用户自主选择（精细控制每 token 权限） |
| 多仓支持 | 一个 token 覆盖用户有权限的所有仓库（官方 plugin 统一 server） | 每仓独立 token 环境变量（`DMSEEK_GH_TOKEN_<REPO_SLUG_UPPER>`） |
| 企业 SSO | 支持（浏览器跳转 GitHub → 企业 SSO 拦截） | 支持（PAT 创建时关联 SSO 授权） |
| 用户群体 | 非研发用户（PM/测试）、研发用户 | 高级用户、DevOps、CI 维护者 |
| 前置依赖 | 无 | 无 |

### 3.2 选择决策树

```
用户场景
  │
  ├─ 有浏览器？ ──Yes── 交互式桌面环境
  │                      │
  │                      ├─ 推荐：OAuth 路径
  │                      │  /plugin install github → /mcp → Authenticate
  │                      │
  │                      └─ 备选：PAT 路径
  │                         手动创建 token → 设环境变量
  │
  └─ 无浏览器？ ──No─── headless / CI / SSH
                         │
                         └─ 唯一选择：PAT 路径
                            在另一台机器创建 token → 搬运到目标环境设环境变量
```

### 3.3 可互相替换

- 两条路径产出的 GitHub MCP 工具名完全一致（均为 `mcp__github__*`，server 名 `github`）。
- repo-tracer 的 L1 `tools` 白名单保持不变——无论 OAuth 还是 PAT，工具前缀都是 `mcp__github__*`。
- 用户可以从 OAuth 切换到 PAT（OAuth 失效时），反之亦然（有浏览器后从 PAT 升级到 OAuth）。

## 4. MCP Server 配置方案

### 4.1 OAuth 路径的 MCP 配置

**不需要任何 `.mcp.json` 配置**。官方 GitHub Plugin（`github@claude-plugins-official`）自行注册 MCP server `github`，认证由 Claude Code keychain 管理。用户只需：

1. `/plugin install github` — 安装官方 plugin
2. `/mcp` → 选择 `github` → 点击 Authenticate — 浏览器完成 OAuth

完成以上两步后，`mcp__github__*` 工具即可在所有 teammate 的会话中使用（但只有 repo-tracer 的 L1 `tools` 白名单包含这些工具）。

### 4.2 PAT 路径的 MCP 配置

PAT 路径使用 GitHub Copilot 托管 MCP（当前 README 中记录的方案）。

**`.mcp.json` 配置**（参考 `mcp-servers.shared.placeholder.jsonc`）：

```jsonc
{
  "mcpServers": {
    "github": {
      "type": "url",
      "url": "https://api.githubcopilot.com/mcp/",
      "headers": {
        "Authorization": "Bearer ${DMSEEK_GH_TOKEN_<REPO_SLUG_UPPER>}"
      }
    }
  }
}
```

**关键约束**：
- Token 在 `.mcp.json` 中**只能用 `${DMSEEK_GH_TOKEN_<REPO_SLUG_UPPER>}` 环境变量引用**，绝不写明文。
- 多仓场景：若需要访问多个 GitHub 仓库，每个仓库设独立环境变量。若使用 GitHub Copilot 托管 MCP，一个 token 通常可访问用户有权限的所有仓库（取决于 token scope）。

#### 4.2.1 `.mcp.json` server 名 `github` 的四种场景行为矩阵（critic A2）

同一 server 名 `github` 可能来自不同注册源，实际生效行为如下：

| # | 是否安装官方 Plugin | `.mcp.json` 是否有 `github` 条目 | 实际生效的 server `github` | 工具来源 | repo-tracer 白名单行为 |
|---|-------------------|-------------------------------|--------------------------|---------|---------------------|
| 1 | **是**，且已 `/mcp` OAuth 认证 | 无 | 官方 Plugin | `mcp__github__*`（Plugin 工具集） | 白名单全量工具应可用 ✅ |
| 2 | **是**，且已 `/mcp` OAuth 认证 | **有**（PAT 配置） | 官方 Plugin（**Plugin 优先**） | Plugin 工具集，`.mcp.json` 被静默忽略 | 白名单全量工具应可用 ✅（但用户可能以为在用 PAT，实际在用 OAuth） |
| 3 | **否**（未安装/已卸载） | **有**（PAT 配置） | `.mcp.json` | `mcp__github__*`（Copilot MCP 工具集） | 部分工具可能不可用 ⚠️（见 §4.4.2） |
| 4 | **否** | 无 | 无 | 无 | 全部不可用 ❌（远端模式不可用，回退态B本地 git） |

> **场景 2 是关键陷阱（critic B4）**：如果用户同时安装了官方 Plugin 且 `.mcp.json` 中配置了 PAT 的 server `github`，**.mcp.json 条目会被 Plugin 静默忽略**——认证走的是 Plugin OAuth 而非用户期望的 PAT。用户可能疑惑"为什么用了 PAT 但似乎没生效"。setup-guide 需在 PAT 引导时主动检测 Plugin 是否已安装并提示二选一。

**setup-guide 应对**：在 PAT 分支开始时执行 `checkPluginConflict`：

```
PAT 分支前置检查：
  1. 检查官方 GitHub Plugin 是否已安装（/plugin list）
  2. 若已安装 → 提示用户：
     "检测到已安装官方 GitHub Plugin（server github），它会覆盖 .mcp.json 中的同名配置。
      选项A：直接使用 Plugin OAuth（推荐，已有认证）
      选项B：卸载 Plugin 后使用 PAT（/plugin uninstall github）
      选项C：保留两者但注意 PAT 不生效"
  3. 若未安装 → 正常继续 PAT 引导
```

> **注意**：PAT 路径下的 MCP server 名与 OAuth 路径完全一致（均为 `github`）。两条路径不能同时配置（同一 server 名冲突）。用户需二选一——若已安装官方 plugin（server `github` 已由 plugin 注册），`.mcp.json` 中的 `github` 条目会被**静默忽略**（Plugin 优先级更高，无冲突报错）。

### 4.3 与官方 Plugin 的关系

| 维度 | 说明 |
|------|------|
| **关系** | OAuth 路径（官方 plugin 注册）和 PAT 路径（`.mcp.json` 手动配置）是**互斥的二选一**，都注册 server `github` → 工具前缀 `mcp__github__*` |
| **共存策略** | 不共存。如果已安装官方 plugin，`.mcp.json` 中的同名 server 配置会被 plugin 覆盖（plugin 优先级更高） |
| **工具名前缀** | 无论哪条路径，工具名均为 `mcp__github__*`——repo-tracer 的 L1 tools 白名单无需变动 |
| **只读子集** | 两条路径下 repo-tracer 的 tools 白名单都仅包含只读子集（18 个工具：`get_file_contents` / `list_commits` / `get_commit` / `search_code` / `list_branches` / `search_repositories` / `search_issues` / `search_pull_requests` / `get_issue` / `list_issues` / `get_pull_request` / `list_pull_requests` / `get_pull_request_files` / `get_pull_request_status` / `get_pull_request_comments` / `get_pull_request_reviews` / `search_users` / `get_authenticated_user`），不授予任何写工具（`create_*` / `update_*` / `delete_*` / `merge_*` 等均不在白名单） |
| **切换** | 用户卸载官方 plugin → plugin 注册的 server `github` 消失 → `.mcp.json` 中的 PAT 配置生效（反之亦然） |

### 4.4 两条路径的工具名映射表（critic B1）

repo-tracer 的 `tools` 白名单是**逐工具硬编码的精确工具名列表**（当前 18 个），不是通配符 `mcp__github__*`。官方 Plugin 和 GitHub Copilot 托管 MCP 暴露的工具名可能不完全一致——需逐工具核对并决定是否需要维护两套白名单。

#### 4.4.1 当前 repo-tracer 白名单（18 个工具，官方 Plugin 路径）

| # | 工具全名 | 功能 | 来源路径 |
|---|---------|------|---------|
| 1 | `mcp__github__get_file_contents` | 取文件内容 | 官方 Plugin |
| 2 | `mcp__github__list_commits` | 分支提交历史 | 官方 Plugin |
| 3 | `mcp__github__get_commit` | 单次 commit 详情 | 官方 Plugin |
| 4 | `mcp__github__search_code` | 代码搜索 | 官方 Plugin |
| 5 | `mcp__github__list_branches` | 仓库分支列表 | 官方 Plugin |
| 6 | `mcp__github__search_repositories` | 仓库搜索 | 官方 Plugin |
| 7 | `mcp__github__search_issues` | Issue/PR 搜索 | 官方 Plugin |
| 8 | `mcp__github__search_pull_requests` | PR 搜索 | 官方 Plugin |
| 9 | `mcp__github__get_issue` | 单条 Issue 详情 | 官方 Plugin |
| 10 | `mcp__github__list_issues` | Issue 列表 | 官方 Plugin |
| 11 | `mcp__github__get_pull_request` | 单条 PR 详情 | 官方 Plugin |
| 12 | `mcp__github__list_pull_requests` | PR 列表 | 官方 Plugin |
| 13 | `mcp__github__get_pull_request_files` | PR 变更文件列表 | 官方 Plugin |
| 14 | `mcp__github__get_pull_request_status` | PR 状态检查 | 官方 Plugin |
| 15 | `mcp__github__get_pull_request_comments` | PR 评论 | 官方 Plugin |
| 16 | `mcp__github__get_pull_request_reviews` | PR review | 官方 Plugin |
| 17 | `mcp__github__search_users` | 用户搜索 | 官方 Plugin |
| 18 | `mcp__github__get_authenticated_user` | 当前认证用户 | 官方 Plugin |

#### 4.4.2 PAT 路径（GitHub Copilot 托管 MCP）工具名差异分析

GitHub Copilot 托管 MCP（`https://api.githubcopilot.com/mcp/`）的工具集可能与官方 Plugin 存在差异：

| 潜在差异维度 | 可能性 | 影响 |
|-------------|--------|------|
| 工具数量不同 | **高**——Copilot MCP 可能暴露更多/更少的工具 | 需实测确认实际注册的工具列表 |
| 同名工具参数不同 | **中**——基础工具（`get_file_contents` / `list_commits` / `get_commit` / `search_code`）通常兼容 | 核心溯源 4 工具的兼容性需实测 |
| 工具名格式不同 | **低**——同为 server `github`，前缀应相同 | 格式应一致但需实测 |

#### 4.4.3 两套白名单策略（设计决策）

**推荐：单一白名单 + 运行时容错**（非维护两套完整白名单）

```
决策逻辑：
  ├─ repo-tracer tools 白名单 = 官方 Plugin 的已验证工具集合（18 个，当前值）
  │      这是"已知正确"的基线
  │
  ├─ PAT 路径下：
  │     - 实际可调用工具 = 白名单工具 ∩ Copilot MCP 实际注册工具
  │     - 部分工具可能不可用（Copilot MCP 未暴露）→ repo-tracer 自检时
  │       逐个 `mcp__github__*` 工具探测可用性，标注缺失项
  │
  └─ 不维护两套并行白名单的原因：
      - 两套白名单的维护成本高（每次 Plugin 更新/Copilot MCP 更新都需同步）
      - 运行时自检已能发现工具缺失并降级
      - 核心溯源工具（`get_file_contents` / `list_commits` / `get_commit` / `search_code`，共4个）
        是 GitHub REST API 的基础操作，两条路径大概率都支持
```

**repo-tracer 自检适配**（需在 §0 启动自检中增加 PAT 路径工具可用性探测）：

```
OAuth 路径自检：逐一探测 tools 白名单中所有18个工具
  ✅ mcp__github__get_file_contents
  ✅ mcp__github__list_commits
  ...
  → 全量通过 → "OAuth ✅"

PAT 路径自检：逐一探测 tools 白名单中所有18个工具
  ✅ mcp__github__get_file_contents
  ✅ mcp__github__list_commits
  ⚠️ mcp__github__get_pull_request_reviews 不可用
  ...
  → 部分缺失 → "PAT ⚠️（3/18 工具不可用：get_pull_request_reviews, ...）"
  缺失工具不影响核心溯源（取码/取史），可能影响 PR 关联 commit 发现
```

**实施阶段待办**（T3 core-dev-2）：在 PAT 路径（GitHub Copilot 托管 MCP）下实测 18 个工具是否全部可用，产出差异清单。如有差异且影响核心功能，再决定是缩减白名单还是提示用户切回 OAuth。

**架构示意**：

```
┌──────────────────────────────────────────────────────┐
│                 repo-tracer                           │
│        tools: mcp__github__* (只读子集)               │
│        声明区块：仅 GitHub plugin 只读子集            │
├──────────────────────────────────────────────────────┤
│                                                      │
│  OAuth 路径                     PAT 路径              │
│  ┌─────────────────┐    ┌──────────────────┐         │
│  │ 官方 GitHub      │    │ .mcp.json:       │         │
│  │ Plugin 注册      │    │ github server    │         │
│  │ server: github   │    │ url: copilot MCP │         │
│  │ 认证: keychain   │    │ token: ${ENV}    │         │
│  └─────────────────┘    └──────────────────┘         │
│         ↑ 互斥二选一 ↑                                │
│                                                      │
│  工具前缀一致：mcp__github__*                         │
└──────────────────────────────────────────────────────┘
```

## 5. 凭据安全

### 5.1 两条路径的安全对比

| 安全维度 | OAuth 路径 | PAT 路径 |
|----------|-----------|----------|
| 凭据存储 | Claude Code keychain（操作系统级加密） | 操作系统环境变量 |
| 明文落盘 | **零**——token 不写入任何文件 | **零**——`.mcp.json` 仅含 `${VAR}` 占位，不写明文 |
| 明文传输 | 仅 token 交换时经 HTTPS（TLS 加密） | 仅 MCP server 请求时经 HTTPS Header |
| 泄漏风险 | 低——keychain 隔离，进程外不可读 | 中——环境变量可被子进程继承，`env` 命令可列出变量名（但值需显式读取） |
| 轮换难度 | 低——/mcp 重新授权即可 | 中——需到 GitHub Settings 重新生成 token、更新环境变量 |
| 最小权限 | scope 由 plugin 预定义（只读倾向） | 取决于用户创建 token 时选择的 scope（可能过度授权） |

### 5.2 安全铁律

1. **skill 全程不接收、不存储 token 明文**：setup-guide skill 在引导用户时，绝不要求用户将 token 粘贴到对话中。用户在自己的终端执行设置命令，skill 不接触明文。
2. **`.mcp.json` 零明文**：任何 MCP 配置文件只允许 `${DMSEEK_*}` 环境变量引用，绝不写 token 明文。
3. **PAT 最小权限原则**：引导用户创建 PAT 时，明确建议 scope 选 `repo`（私有仓库只读访问），不勾选 `admin`、`write`、`delete` 等写权限。
4. **OAuth scope 最小权限**：仅申请 `repo` 和 `read:org`（且 `read:org` 为可选），不申请任何写权限 scope。
5. **终端历史泄漏防范（critic D1）**：用户在终端中直接输入含 token 明文的命令（如 `[Environment]::SetEnvironmentVariable("...", "ghp_xxxx", "User")`）会**持久化写入 PSReadLine 历史文件**（Windows `~\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt`），这是独立于 `.mcp.json` 的第二泄漏面。引导用户时须采用以下防护之一：
   - **Windows（推荐）**：使用 `Read-Host -MaskInput` 交互式输入 token，不留在命令行历史中：
     ```powershell
     # 引导用户执行（token 输入时显示为 ***，不进命令历史）
     $token = Read-Host -Prompt "请粘贴 GitHub PAT" -MaskInput
     [Environment]::SetEnvironmentVariable("DMSEEK_GH_TOKEN_<REPO_SLUG>", $token, "User")
     ```
   - **macOS/Linux**：`read -s -p "请粘贴 GitHub PAT: " token && export DMSEEK_GH_TOKEN_<REPO_SLUG>=$token`（`-s` 禁止回显，不写 bash 历史）。
   - **通用（跨平台，推荐）**：引导用户用系统环境变量设置 GUI 面板（Windows"编辑系统环境变量"→"环境变量"），完全不经过终端命令行。
   - **事后清理（如已直接执行含明文的命令）**：提示用户清除 PowerShell 历史行 `Clear-History` 或手动编辑 `ConsoleHost_history.txt` 删除对应行。

### 5.3 `design-mcp-config-shape.md` "零环境变量" 分路径标注（critic C1）

`design-mcp-config-shape.md` 当前声明的"零明文、零环境变量"适用于 **OAuth 路径**（官方 Plugin 自管 OAuth）。引入 PAT 路径后，该声明需按路径区分：

| 路径 | 凭据落盘 | 环境变量 | `.mcp.json` |
|------|---------|----------|-------------|
| OAuth（官方 Plugin） | 零（token 在 Claude Code keychain） | 零（不需要） | 零（plugin 自注册） |
| PAT | 零（`.mcp.json` 仅含 `${VAR}` 占位） | **有**（`DMSEEK_GH_TOKEN_*`，用户自设） | **有**（server `github` 条目，但仅含 `${VAR}` 引用） |

建议在 `design-mcp-config-shape.md` 的"凭据由 Claude Code keychain 管理，零明文、零环境变量"之后加注："（以上指 OAuth 路径；PAT 回退路径使用环境变量 `${DMSEEK_GH_TOKEN_*}`，但 `.mcp.json` 仍零明文）"。

## 6. 跨平台方案

### 6.1 浏览器打开

Claude Code 的 `/mcp` Authenticate 流程由 Claude Code 自身管理浏览器打开——dm-seek 无需自行实现跨平台 `open` 命令。若未来需要在 skill 中手动触发浏览器打开（如引导用户注册 OAuth App 时打开 GitHub 页面）：

| 平台 | 命令 | 示例 |
|------|------|------|
| Windows | `start "" "URL"` | `start "" "https://github.com/settings/developers"` |
| macOS | `open "URL"` | `open "https://github.com/settings/developers"` |
| Linux | `xdg-open "URL"` | `xdg-open "https://github.com/settings/developers"` |

### 6.2 localhost callback 方案

- **端口选择**：Claude Code 默认使用 `18765` 作为 OAuth 回调端口。若端口被占用，递增尝试 `18766`、`18767`。
- **端口冲突处理**：Claude Code 在启动本地 HTTP 监听时检测端口可用性，自动 fallback 到下一个端口。
- **防火墙考量**：localhost loopback（`127.0.0.1`）通常不受防火墙限制——操作系统不将 loopback 流量发送到网络接口。企业防火墙不影响 localhost 回调。
- **企业代理环境**：部分企业使用 HTTP 代理（`HTTP_PROXY` / `HTTPS_PROXY` 环境变量），需确保 `localhost` 和 `127.0.0.1` 在 `NO_PROXY` 列表中（通常是默认行为）。

### 6.3 企业网络限制场景

少数极端环境（如 VDI、堡垒机）可能：
- 禁用浏览器
- 限制除企业代理外的所有出站连接
- 无法绑定 localhost 端口

这些场景统一走 PAT 路径——用户在另一台有浏览器的机器上创建 PAT，搬运 token 到受限环境设置为环境变量。

## 7. 独占一致性

### 7.1 工具名不变

无论 OAuth 路径还是 PAT 路径，GitHub MCP 工具名均为 `mcp__github__*`。这意味着：

- repo-tracer 的 L1 `tools` 白名单（`mcp__github__*`，只读子集）完全不变。
- jira-tracer 的 `mcp__atlassian__*` 工具名不变。
- 其他 agent（code-analyst、kb-keeper、synthesizer、evidence-verifier、dongmei-ma）的 `tools` 字段不出现 `mcp__` 工具——不变。

### 7.2 独占边界不变

| agent | GitHub MCP 权限 | 变动 |
|-------|----------------|------|
| repo-tracer | `mcp__github__*`（只读子集，独占） | **无** |
| code-analyst | 无（远端经 repo-tracer 取） | **无** |
| 其他 agent | 无 | **无** |

### 7.3 三道防线不变

- **L1 技术层**：`tools` 白名单，OAuth/PAT 路径均生效。官方 plugin 注册的 MCP server 同样受白名单约束。
- **L2 声明层**：每个 agent 的「允许使用的 MCP 服务」声明区块不变。
- **兜底校验层**：evidence-verifier 的边界违规校验不变。

### 7.4 新增的 OAuth 配置不改变现有独占边界

OAuth 路径仅改变**认证方式**（从 setup-guide 引导 `gh auth login` 的迂回方式，变为 plugin 直接在 `/mcp` 界面自管 OAuth），不改变**授权方式**（`tools` 白名单）。MCP server 名 `github` 不变，工具前缀不变，独占归属不变。

## 8. 与 setup-guide 的集成点

### 8.1 当前 setup-guide 流程

当前 setup-guide（`.claude/skills/setup-guide/SKILL.md`）的 GitHub 认证路径：

```
0.1 GitHub Plugin 引导（旧版本，v1.2 已移除 gh CLI 步骤）
  1. ★ 检测 gh CLI (gh --version)           ← 历史迂回，v1.2 移除
  2. ★ 安装 gh CLI (winget/brew/apt)         ← 历史迂回，v1.2 移除
  3. ★ gh auth login (浏览器 Web 流程)        ← 历史迂回，v1.2 移除
  4. 安装 GitHub Plugin (/plugin install github)  ← Plugin 自己可在 /mcp 直接 OAuth
  5. 验证 mcp__github__* 工具可用

  注：步骤 1-3 是历史迂回——官方 Plugin 的 /mcp Authenticate 与 gh CLI 无关。
  v1.2 改造后 OAuth 路径：/plugin install github → /mcp Authenticate，两步完成。
```

### 8.2 改造后的双轨引导

setup-guide §0.1 处分支出两条路径：

```
§0.1 GitHub 认证引导（双轨选择）

  环境探测：
    - 是否有浏览器？ → yes/no
    - 是否已安装官方 GitHub Plugin？ → /plugin list | grep github

  推荐路径判断：
    ├─ 有浏览器 + 已装 plugin → OAuth 路径（推荐）
    ├─ 有浏览器 + 无 plugin → 引导安装 plugin → OAuth 路径
    └─ 无浏览器 → PAT 路径

  OAuth 分支（推荐）：
    1. 检查 GitHub Plugin 是否已安装
       - /plugin list 确认 github@claude-plugins-official 存在
       - 未安装 → 引导 /plugin install github
    2. 提示用户在 /mcp 界面完成 OAuth 授权
       - 打开 /mcp → 选择 github → Authenticate
       - 浏览器自动打开 → 用户登录 GitHub 并授权
    3. 验证：mcp__github__get_file_contents 等工具可用性
    4. 失败处理：提示重新 Authenticate / 检查网络

  PAT 分支（备选）：
    1. 引导用户创建 GitHub Personal Access Token
       - 打开 https://github.com/settings/tokens
       - New personal access token (classic)
       - Scope: repo (勾选)
    2. 引导用户设置环境变量
       - 用户在自己的终端执行：
         Windows: (防终端历史泄漏) $token = Read-Host -Prompt "请粘贴 GitHub PAT" -MaskInput; [Environment]::SetEnvironmentVariable("DMSEEK_GH_TOKEN_<REPO_SLUG>", $token, "User") (token 输入时显示为 ***，不进 PSReadLine 历史)
         macOS/Linux: (防终端历史泄漏) read -s -p "请粘贴 GitHub PAT: " token && export DMSEEK_GH_TOKEN_<REPO_SLUG>=$token (-s 禁止回显，不写 bash 历史)
       - skill 绝不接收 token 明文
    3. 配置 .mcp.json（如使用 GitHub Copilot 托管 MCP）
    4. 验证：mcp__github__* 工具可用性
    5. 失败处理：提示检查 token scope / 网络

  每步提供跳过出口：
    - OAuth 失败 → 提示切到 PAT 路径
    - PAT 创建失败 → 提示检查 GitHub 权限
```

	### 8.3 gh CLI 移除说明（v1.2）

dm-seek 不依赖 `gh` CLI。OAuth 路径和 PAT 路径均不需要 `gh` CLI：

- **OAuth 路径**：官方 Plugin 在 `/mcp` 界面直接完成 OAuth 授权，与 `gh` CLI 无关。引导步骤为 `/plugin install github → /mcp → Authenticate`，两步完成。
- **PAT 路径**：用户手动创建 PAT 并设环境变量，与 `gh` CLI 无关。

`gh` CLI 是用户可自行安装使用的 GitHub 命令行工具（如 `gh auth status` 排查问题），但**不是 dm-seek 的依赖项**——setup-guide 不检测、不安装、不引导 `gh` CLI。

## 9. 风险与限制

### 9.1 已知风险

1. **官方 Plugin 的 `/mcp` OAuth 流程尚未在 headless 模式验证**
   - Claude Code 的 `/mcp` Authenticate 流程依赖 GUI 和浏览器。在纯 headless（SSH、无 X11）环境下是否支持、是否有 non-interactive fallback，需要实测确认。
   - 缓解：headless 场景默认走 PAT 路径。

2. **官方 GitHub Plugin 的 OAuth 依赖 Claude Code 版本**
   - 较老的 Claude Code 版本可能不支持 `/mcp` 界面的 OAuth 流程。
   - 缓解：setup-guide 探测 Claude Code 版本，过低时提示升级或直接走 PAT 路径。

3. **localhost callback 端口可能被安全软件拦截**
   - 某些企业安全软件（端点保护、DLP）可能监控或拦截 localhost 端口的 HTTP 流量。
   - 缓解：端口冲突递增尝试；极端情况走 PAT 路径。

4. **GitHub API rate limit（OAuth 与 PAT 区分）**
   - **OAuth 路径（官方 Plugin）**：GitHub OAuth App 有 rate limit（每个 user 每小时 5000 请求）。正常使用 dm-seek 不会触及，但批量 KB 初始化（全仓扫 commit 历史）可能触发。
   - **PAT 路径**：Personal Access Token 的 rate limit 独立于 OAuth App——fine-grained PAT 有 5000 请求/小时的 limit，classic PAT 以实际 GitHub 账户 plan 为准。OAuth 耗尽时切 PAT 不能绕过 rate limit（两者不共享计数池，但通常同为 5000/h）。
   - 缓解：repo-tracer 的取码/取史调用合并批量请求，减少 API 调用次数。KB 初始化时建议分批+延迟策略，避免一次性扫全仓。

5. **无法预置 client_secret**（仅方案 B 涉及）
   - 如果未来需要支持用户自行注册 OAuth App（§2.2.1 方案 B），`client_secret` 只能由用户生成，dm-seek 无法预置。
   - 缓解：`client_secret` 通过环境变量 `${DMSEEK_GH_OAUTH_CLIENT_SECRET}` 注入，绝不明文落盘。

### 9.2 设计限制

1. **两条路径互斥，不可同时使用**：同一 MCP server 名（`github`）不能同时由官方 plugin 和 `.mcp.json` 注册。用户需二选一。
2. **OAuth token 的 scope 由官方 plugin 控制**：dm-seek 无法定制 scope——如果官方 plugin 申请了超出最小权限的 scope，dm-seek 无法缩减。
3. **PAT 路径的多仓 token 管理仍有一定复杂度**：一个 PAT 可覆盖多仓（scope 够的话），但 README 中记录的 `DMSEEK_GH_TOKEN_<REPO_SLUG_UPPER>` 模式暗示每仓独立 token。实现时需澄清：是多仓共享一个 PAT 还是每仓各自一个 PAT。

### 9.3 待定项

| 待定项 | 决策时机 | 预期窗口 | 依赖 |
|--------|---------|---------|------|
| PAT 路径的 MCP server 选型 | 实现期（T3） | 2026-06-20 前 | 实测 GitHub Copilot 托管 MCP vs 官方 GitHub MCP Server 的兼容性 |
| PAT 路径工具名差异清单（§4.4） | 实现期（T3） | 2026-06-20 前 | PAT 路径下 18 个工具逐一实测 |
| OAuth `/mcp` 流程 headless 兼容性 | 验证期（T5） | 2026-06-25 前 | qa-engineer-2 实测 SSHPowerShell remote 场景 |
| OAuth 路径下多 GitHub 账号支持 | 按需 | v1.2+ | 用户反馈 |
| GitHub Enterprise Server (GHES) 支持 | 按需 | v1.2+ | 用户反馈（企业级私有 GitHub 实例需要自定义 OAuth endpoint） |
| `design-mcp-config-shape.md` 同步更新（§5.3 分路径标注） | 实现期（T3） | 2026-06-20 前 | 本文通过 critic 审查后同步 |
