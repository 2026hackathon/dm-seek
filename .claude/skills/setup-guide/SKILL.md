---
name: setup-guide
description: 马冬梅计划开箱引导/配置——引导安装官方 GitHub/Atlassian plugin（浏览器 SSO 授权，零手动 token）；探测本地多仓与 obsidian CLI；凭据由 Claude Code keychain 管理，零明文。
---

# setup-guide — 开箱引导 / 配置（跨 Win/macOS）

> 依据 `.claude/rules/design-mcp-config-shape.md`（MCP 由官方 plugin 自行注册）+ `runtime-spec.md`。凭据由 Claude Code keychain 管理，零明文、零环境变量。

## 何时用
- 首次导入 dm-seek 配置包；或新增 git 仓库 / 补配凭据 / 配置 Jira。

## 探测/手填界线（硬性）
- **可自动探测（非敏感）**：本地仓库路径、`git remote get-url origin` 推断的 repoSlug、平台与默认 shell、obsidian CLI 二进制位置、vault 路径。
- **必须用户手填（敏感）**：所有 token / 邮箱——由用户粘贴到自己终端执行，skill 不接收明文。

## 步骤

### 0. 官方 Plugin 引导（优先推荐 — 浏览器 SSO 授权）

> 推荐用户使用官方 Claude Code plugin 认证，**无需手动创建 token**——浏览器登录即可完成授权，支持公司 SSO。每一步提供跳过出口，失败不回滚已完成的步骤。

#### 0.1 GitHub Plugin 引导

1. **检测 `gh` CLI**
   - 执行 `gh --version`
   - 已安装 → 跳到步骤 3

2. **[自动] 安装 `gh` CLI**（需用户确认）
   - 检测平台：
     - Windows（winget）：`winget install --id GitHub.cli`
     - Windows（无 winget）：提示打开 https://cli.github.com 手动下载
     - macOS（brew）：`brew install gh`
     - Linux（apt）：`sudo apt install gh`
   - 安装后验证：`gh --version`
   - 安装失败 → 提示手动下载 + **提示手动安装后重试**

3. **登录 `gh`**
   - 执行 `gh auth login`
   - 交互指引：选择 GitHub.com → HTTPS → Login with a web browser
   - 浏览器自动打开 → 用户完成 GitHub 登录（公司 SSO 如适用）
   - 验证：`gh auth status`
   - 失败 → **提示手动安装后重试**

4. **安装 GitHub Plugin**
   - 引导用户执行 `/plugin install github@claude-plugins-official`
   - 已安装则跳过

5. **验证**：重启 Claude Code 后，repo-tracer 自检会确认 `mcp__github__get_file_contents` 等工具可用

#### 0.2 Jira Plugin 引导

1. **安装 Atlassian Plugin**
   - 引导用户执行 `/plugin install atlassian@claude-plugins-official`
   - 已安装则跳过
   - 失败 → **提示手动安装后重试**

2. **OAuth 认证**
   - 引导用户启动 Claude Code，运行 `/mcp`
   - 在 MCP 面板中找到 Atlassian → 选择 Authenticate
   - 浏览器自动打开 → 跳转 Atlassian 登录页 → 公司 SSO 拦截 → 完成登录
   - 授权页面确认 → Accept
   - Claude Code 自动保存 token（零明文落配置文件）

3. **验证**：jira-tracer 自检会确认 `mcp__atlassian__search_issues` 等工具可用

#### 0.3 跳过与回退

每一步都提供跳过出口：
- `gh` CLI 安装失败 → 提示手动安装后重试
- `gh auth login` 失败 → 提示检查网络/SSO 后重试
- plugin 安装失败 → 提示检查 `/plugin marketplace update claude-plugins-official`

任何步骤失败不回滚已完成的步骤——已安装的 `gh` CLI / plugin 保留。

---

### 1. 探测多仓（非敏感、自动）
扫描用户指定目录，发现 `.git` → `git remote get-url origin` 推断 repoSlug。本地多仓信息供 code-analyst 和 repo-tracer 路由使用。

### 2. obsidian CLI 路径探测与注入
- 探测二进制（Windows `D:\obsidian\Obsidian.com`、macOS 名不同/无 `.com` 后缀），设 `${DMSEEK_OBSIDIAN_CLI}` 供 kb-keeper 使用。CLI 不在 PATH，须显式路径。
- **vault 根选址校验（硬性）**：探测/确认 vault 路径时，若 **vault 根目录或其路径任一父段以 `.` 开头**（如 `~/.obsidian-vault/`）→ **提示用户 obsidian CLI 不可读、请改用非 dot 路径**。

### 3. 连通性自检
- 验证官方 plugin 工具可用性：`mcp__github__get_file_contents` / `mcp__atlassian__search_issues`
- 失败时提示「plugin 未认证（重跑 /mcp Authenticate）」或「plugin 未安装（重跑 /plugin install）」
- repo-tracer / jira-tracer 自检会进一步确认各自域的工具状态

## 安全铁律
- 凭据由 Claude Code keychain 管理（OAuth），**零明文落配置文件、零环境变量**。
- skill 全程不接收、不存储任何 token 明文。
