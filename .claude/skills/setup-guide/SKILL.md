---
name: setup-guide
description: 马冬梅计划开箱引导/配置——双轨 GitHub 认证（OAuth 浏览器授权 + PAT 环境变量备选）；Atlassian plugin OAuth；探测本地多仓与 obsidian CLI；凭据零明文。
---

# setup-guide — 开箱引导 / 配置（跨 Win/macOS）

> 依据 `.claude/rules/design-mcp-config-shape.md`（MCP 由官方 plugin 自行注册）+ `design-github-oauth-login.md`（OAuth/PAT 双轨架构）。凭据零明文，OAuth 路径 token 由 Claude Code keychain 管理，PAT 路径 token 仅存环境变量。

## 何时用
- 首次导入 dm-seek 配置包；或新增 git 仓库 / 补配凭据 / 配置 Jira。

## 探测/手填界线（硬性）
- **可自动探测（非敏感）**：本地仓库路径、`git remote get-url origin` 推断的 repoSlug、平台与默认 shell、obsidian CLI 二进制位置、vault 路径。
- **必须用户手填（敏感）**：所有 token——由用户粘贴到自己终端执行，skill 不接收明文。

---

## 0. GitHub 认证引导（双轨选择）

> dm-seek 提供两条 GitHub 认证路径，互斥二选一。推荐有浏览器的用户使用 OAuth 路径（官方 Plugin），无浏览器/headless 场景使用 PAT 路径。
>
> **dm-seek 不依赖 `gh` CLI**——OAuth 和 PAT 两条路径均不需要 `gh` CLI。

### 0.0 环境探测

探测以下信息以推荐路径：

1. **浏览器可用性**（推荐路径判断）：
   - 交互式桌面环境（GUI 可用）→ 有浏览器 → 推荐 OAuth
   - headless / SSH / CI / 无图形界面 → 无浏览器 → 只能 PAT

2. **官方 GitHub Plugin 是否已安装**：
   - 检查 `/plugin list` 输出是否含 `github@claude-plugins-official`
   - 已安装 + 已 /mcp Authenticate → OAuth 就绪
   - 已安装但未 Authenticate → 提示完成 OAuth

**推荐路径判断**：

```
├─ 有浏览器 + 已装 plugin + 已 Authenticate → OAuth 路径（就绪）
├─ 有浏览器 + 已装 plugin + 未 Authenticate → OAuth 路径（补 Authenticate）
├─ 有浏览器 + 未装 plugin → 引导安装 plugin → OAuth 路径
└─ 无浏览器 → PAT 路径
```

---

### 0.1 OAuth 分支（推荐，有浏览器）

> 官方 GitHub Plugin 在 `/mcp` 界面直接完成 OAuth 授权。与 `gh` CLI 无关。

**步骤**：

1. **检查 GitHub Plugin 是否已安装**
   - `/plugin list` 确认 `github@claude-plugins-official` 存在
   - 已安装 → 跳到步骤 2
   - 未安装 → 引导执行 `/plugin install github@claude-plugins-official`
   - 安装失败 → 提示「检查网络连接后重试 `/plugin install github`」→ 提供切到 PAT 路径的出口

2. **完成 OAuth 授权**
   - 引导用户打开 `/mcp` 面板
   - 在 MCP 面板中找到 `github` → 点击 Authenticate
   - 浏览器自动打开 → 跳转 GitHub 授权页（`https://github.com/login/oauth/authorize`）
   - 用户登录 GitHub（支持公司 SSO）→ 确认授权
   - 授权完成后 Claude Code 自动保存 token（keychain 加密存储，零明文）

3. **验证**
   - 验证 `mcp__github__get_file_contents` 等工具可用
   - 验证方法：调用 `mcp__github__get_authenticated_user` 确认连通性
   - 成功 → "GitHub OAuth ✅"
   - 失败：
     - 401/403 → 提示「OAuth token 可能已失效，请在 `/mcp` 界面重新 Authenticate」
     - 网络/超时 → 提示「检查网络连接后重试 `/mcp` Authenticate」
     - 反复失败 → 提示切到 PAT 路径

4. **跳过出口**
   - OAuth 失败 → 提示切到 PAT 路径（见 §0.2）
   - Plugin 安装失败 → 提示检查 `/plugin marketplace update claude-plugins-official`
   - 任何步骤失败不回滚已完成的步骤

---

### 0.2 PAT 分支（备选，无浏览器/headless）

> 手动创建 GitHub Personal Access Token，通过环境变量注入。适用于 headless、CI/CD、远程 SSH、企业网络限制浏览器跳转等场景。

**前置检查：Plugin 冲突检测**

在开始 PAT 引导前，检查官方 GitHub Plugin 是否已安装：

```
checkPluginConflict：
  1. /plugin list | grep github
  2. 若已安装官方 GitHub Plugin（server github）→ 提示用户：
     "检测到已安装官方 GitHub Plugin（server github）。
      官方 Plugin 与 .mcp.json 中的 PAT 配置使用同一 server 名 `github`——
      Plugin 优先级更高，PAT 配置将被静默忽略。
      选项A：直接使用 Plugin OAuth（推荐，已有认证，见 §0.1）
      选项B：卸载 Plugin 后使用 PAT（/plugin uninstall github）
      选项C：保留两者——但注意 .mcp.json 中的 PAT 不生效"
  3. 若未安装 → 正常继续 PAT 引导
```

**步骤**：

1. **引导用户创建 GitHub Personal Access Token**
   - 引导用户打开 https://github.com/settings/tokens
   - New personal access token (classic)
   - Note: `dm-seek-<repo>`（方便识别）
   - Expiration: 按需（建议 90 天或更长）
   - **Scope（最小权限原则）**：勾选 `repo`（私有仓库只读访问）
     - 不勾选 `admin`、`write:packages`、`delete_repo` 等写权限
     - 如需组织信息可额外勾选 `read:org`（可选）
   - 点击 Generate token → **立即复制**（离开页面后不可见）

2. **引导用户设置环境变量（防终端历史泄漏）**
   - **skill 绝不接触 token 明文**——用户在本地终端执行，skill 仅提供命令模板
   - Windows（推荐方式）：
     ```powershell
     # token 输入时显示为 ***，不进 PSReadLine 命令历史
     $token = Read-Host -Prompt "请粘贴 GitHub PAT" -MaskInput
     [Environment]::SetEnvironmentVariable("DMSEEK_GH_TOKEN_<REPO_SLUG>", $token, "User")
     ```
     替换 `<REPO_SLUG>` 为实际仓库标识（如 `HDR_DELIVERY`，与 repoSlug 对应，全大写、连字符变下划线）。
     **设置后需重启终端**使环境变量生效。
   - macOS/Linux（推荐方式）：
     ```bash
     # -s 禁止回显，不写 bash 历史
     read -s -p "请粘贴 GitHub PAT: " token && export DMSEEK_GH_TOKEN_<REPO_SLUG>=$token
     ```
   - **通用（跨平台，最安全）**：引导用户通过系统 GUI 设置：
     - Windows：设置 → 系统 → 关于 → 高级系统设置 → 环境变量 → 新建用户变量
     - macOS：`launchctl setenv DMSEEK_GH_TOKEN_<REPO_SLUG> <token>` 或写入 `~/.zshrc`（注意文件权限 `chmod 600`）
   - **事后清理（重要）**：如果用户已经直接在命令行中执行了含 token 明文的命令（如直接 `export DMSEEK_GH_TOKEN=ghp_xxxx`），提示：
     - Windows：`Clear-History` 或手动编辑 `%APPDATA%\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt`
     - macOS/Linux：`history -d <行号>` 或编辑 `~/.bash_history` / `~/.zsh_history`

3. **配置 `.mcp.json`**
   - 在项目根目录 `.mcp.json` 的 `mcpServers` 中添加（参考 `templates/mcp-servers.shared.placeholder.jsonc`）：
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
   - Token **只能用 `${DMSEEK_GH_TOKEN_*}` 环境变量引用**，绝不写明文。
   - 多仓场景：如多个仓库共享同一 PAT（scope 涵盖），可共用同一环境变量；如需每仓独立 token，各自设独立环境变量。

4. **验证**
   - 重启 Claude Code 使 `.mcp.json` 生效
   - 验证 `mcp__github__get_authenticated_user` 连通性
   - 成功 → "GitHub PAT ✅"
   - 失败：
     - 401 → 提示「PAT 可能已过期或被撤销，请到 https://github.com/settings/tokens 重新生成」
     - 403 → 提示「PAT 权限不足，请检查 scope 是否包含 `repo`」
     - 工具不可用 → 提示「PAT 路径下部分工具可能不可用（Copilot 托管 MCP 与官方 Plugin 工具集有差异），核心溯源工具（get_file_contents/list_commits/get_commit/search_code）通常兼容」

5. **跳过出口**
   - PAT 创建失败 → 提示检查 GitHub 账号权限
   - 验证失败 → 提示切回 OAuth 路径（如果有浏览器）
   - 任何步骤失败不回滚已完成的步骤

---

### 0.3 环境探测：浏览器有无

> 不检测 `gh` CLI——dm-seek 不依赖 `gh` CLI。

判断方法：
- 交互式桌面环境（Claude Code 桌面版 / IDE 扩展）→ 有浏览器
- SSH 远程 / headless 终端 / CI runner → 无浏览器
- 用户直接说明 → 以用户说明为准

---

## 1. Atlassian (Jira) Plugin 引导

1. **安装 Atlassian Plugin**
   - 引导用户执行 `/plugin install atlassian@claude-plugins-official`
   - 已安装则跳过
   - 失败 → 提示「检查网络后重试 `/plugin install atlassian@claude-plugins-official`」

2. **OAuth 认证**
   - 引导用户打开 `/mcp` 面板
   - 在 MCP 面板中找到 Atlassian → 选择 Authenticate
   - 浏览器自动打开 → 跳转 Atlassian 登录页 → 公司 SSO 拦截 → 完成登录
   - 授权页面确认 → Accept
   - Claude Code 自动保存 token（keychain 加密存储，零明文）

3. **验证**
   - jira-tracer 自检会确认 `mcp__atlassian__search_issues` 等工具可用

---

## 2. 探测多仓（非敏感、自动）

扫描用户指定目录，发现 `.git` → `git remote get-url origin` 推断 repoSlug。本地多仓信息供 code-analyst 和 repo-tracer 路由使用。

---

## 3. obsidian CLI 路径探测与注入

- 探测二进制（Windows `D:\obsidian\Obsidian.com`、macOS 名不同/无 `.com` 后缀），设 `${DMSEEK_OBSIDIAN_CLI}` 供 kb-keeper 使用。CLI 不在 PATH，须显式路径。
- **vault 根选址校验（硬性）**：探测/确认 vault 路径时，若 **vault 根目录或其路径任一父段以 `.` 开头**（如 `~/.obsidian-vault/`）→ **提示用户 obsidian CLI 不可读、请改用非 dot 路径**。

---

## 4. 连通性自检

- 验证 MCP 工具可用性：
  - GitHub：`mcp__github__get_authenticated_user`（OAuth 路径）或 `mcp__github__get_file_contents`（PAT 路径）
  - Jira：`mcp__atlassian__search_issues`
- GitHub 失败时：
  - OAuth 路径 → 提示「Plugin 未认证（请在 /mcp 面板重新 Authenticate）」
  - PAT 路径 → 提示「PAT 可能已失效，请检查环境变量和 scope」
- repo-tracer / jira-tracer 自检会进一步确认各自域的工具状态

---

## 安全铁律

- **OAuth 路径**：凭据由 Claude Code keychain 管理，零明文落配置文件、零环境变量。
- **PAT 路径**：token 仅存环境变量，`.mcp.json` 仅含 `${DMSEEK_GH_TOKEN_*}` 占位，零明文落盘。
- **skill 全程不接收、不存储任何 token 明文**——用户在本地终端执行设置命令，skill 不接触 token 明文。
- **PAT 最小权限**：引导用户创建 PAT 时仅勾选 `repo`（只读），不勾选写权限 scope。
- **终端历史泄漏防范**：Windows 使用 `Read-Host -MaskInput`，macOS/Linux 使用 `read -s`，或引导用户通过系统 GUI 设置环境变量。事后提供清理命令历史的方法。
