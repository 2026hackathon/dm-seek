---
name: setup-guide
description: 马冬梅计划开箱引导/配置——优先引导安装官方 GitHub/Atlassian plugin（浏览器 SSO 授权，零手动 token）→ PAT 环境变量 fallback；探测本地多仓与 obsidian CLI；凭据一律不落配置文件。
---

# setup-guide — 开箱引导 / 配置（跨 Win/macOS）

> 依据 `.claude/rules/design-mcp-config-shape.md`（共享 `.mcp.json` + tools 白名单 + 声明区块 + 凭据 ${VAR} 化）+ `.claude/rules/design-jira-mcp-toolmap.md`（Jira env）。**探测非敏感项 + 引导手填敏感项**——skill 全程不接收、不存储任何 token 明文。

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
   - 安装失败 → 提示手动下载 + **跳过到此路径，进入 §3 PAT fallback**

3. **登录 `gh`**
   - 执行 `gh auth login`
   - 交互指引：选择 GitHub.com → HTTPS → Login with a web browser
   - 浏览器自动打开 → 用户完成 GitHub 登录（公司 SSO 如适用）
   - 验证：`gh auth status`
   - 失败 → **跳过到此路径，进入 §3 PAT fallback**

4. **安装 GitHub Plugin**
   - 引导用户执行 `/plugin install github@claude-plugins-official`
   - 已安装则跳过

5. **验证**：重启 Claude Code 后，repo-tracer 自检会确认 `mcp__github__get_file_contents` 等工具可用

#### 0.2 Jira Plugin 引导

1. **安装 Atlassian Plugin**
   - 引导用户执行 `/plugin install atlassian@claude-plugins-official`
   - 已安装则跳过
   - 失败 → **跳过到此路径，进入 §3 PAT fallback**

2. **OAuth 认证**
   - 引导用户启动 Claude Code，运行 `/mcp`
   - 在 MCP 面板中找到 Atlassian → 选择 Authenticate
   - 浏览器自动打开 → 跳转 Atlassian 登录页 → 公司 SSO 拦截 → 完成登录
   - 授权页面确认 → Accept
   - Claude Code 自动保存 token（零明文落配置文件）

3. **验证**：jira-tracer 自检会确认 `mcp__atlassian__search_issues` 等工具可用

#### 0.3 跳过与回退

每一步都提供跳过出口：
- `gh` CLI 安装失败 → "跳过，使用 PAT 替代"
- `gh auth login` 失败 → "跳过，使用 PAT 替代"
- plugin 安装失败 → "跳过，使用 PAT 替代"
- 用户主动选择 "我不用浏览器登录" → 直接跳到 **§3 PAT 环境变量配置**

任何步骤失败不回滚已完成的步骤——已安装的 `gh` CLI / plugin 保留。
用户跳过 §0 后，继续执行下面的 §1~§5（PAT 路径）。

---

### 1. 探测多仓（非敏感、自动）
扫描用户指定目录，发现 `.git` → `git remote get-url origin` 推断 repoSlug（小写、非 `[a-z0-9-]`→`-`）→ 机械生成：
- MCP server 名 `dm-github-<repoSlug>`；token 变量名 `DMSEEK_GH_TOKEN_<REPO_SLUG_UPPER>`（大写、`-`→`_`）。
- 维护「仓↔实例↔token 变量」映射表（`.claude/rules/design-mcp-config-shape.md` §2.3）。

### 2. 写共享 `.mcp.json`
把 GitHub 多仓（每仓一 `dm-github-<repoSlug>` http 条目，端点 `${DMSEEK_GH_MCP_URL:-https://api.githubcopilot.com/mcp/}`、`Authorization: Bearer ${DMSEEK_GH_TOKEN_<...>}`）+ Jira（stdio，`@aashari/mcp-server-atlassian-jira`，env `ATLASSIAN_*=${DMSEEK_JIRA_*}`）写入项目根 `.mcp.json`。模板见 `.claude/rules/templates/mcp-servers.shared.placeholder.jsonc`。
**同步**：把对应 `mcp__dm-github-<repoSlug>__*` 追加进 **repo-tracer 的 `tools` 白名单**（独占承重点；模板 `.claude/rules/templates/agent-tools-allowlist.placeholder.md`）。

### 3. 引导设置环境变量（敏感、手填，跨平台）
逐项提示用户为各 `${DMSEEK_*}` 设置值，输出对应平台命令（**不回显 token 进日志/历史**）：

**Windows (PowerShell)**：
```powershell
[Environment]::SetEnvironmentVariable("DMSEEK_GH_TOKEN_HDR_DELIVERY_PROJECT", "<粘贴-token>", "User")
[Environment]::SetEnvironmentVariable("DMSEEK_JIRA_API_TOKEN", "<粘贴-token>", "User")
$env:DMSEEK_JIRA_SITE_NAME = "<site>"; $env:DMSEEK_JIRA_EMAIL = "<email>"   # 当前会话
```
**macOS / Linux (bash/zsh)**：
```bash
echo 'export DMSEEK_GH_TOKEN_HDR_DELIVERY_PROJECT="<粘贴-token>"' >> ~/.zshrc
echo 'export DMSEEK_JIRA_API_TOKEN="<粘贴-token>"' >> ~/.zshrc
export DMSEEK_JIRA_SITE_NAME="<site>"; export DMSEEK_JIRA_EMAIL="<email>"
```
变量清单见 `.claude/rules/design-mcp-config-shape.md` §4.2。**提醒：设完变量需重启 Claude Code / 终端**，`${VAR}` 才展开。

### 4. obsidian CLI 路径探测与注入
- 探测二进制（Windows `D:\obsidian\Obsidian.com`、macOS 名不同/无 `.com` 后缀），设 `${DMSEEK_OBSIDIAN_CLI}` 供 kb-keeper 使用。CLI 不在 PATH，须显式路径。
- **vault 根选址校验（硬性）**：探测/确认 vault 路径时，若 **vault 根目录或其路径任一父段以 `.` 开头**（如 `~/.obsidian-vault/`、`/home/u/.kb/...`）→ **提示用户该路径 obsidian CLI 不可读（整 vault 瘫痪）、请改用非 dot 路径**。

### 5. 连通性自检 + 增量
- **Plugin 优先**：先验证官方 plugin 工具可用性（`mcp__github__get_file_contents` / `mcp__atlassian__search_issues`）
- **PAT 回退**：plugin 不可用时验证 PAT 实例连接状态（`/mcp` 查看 `dm-github-<repoSlug>` / `jira`）
- 失败时区分「plugin 未认证（重跑 /mcp Authenticate）」vs「PAT token 未设/无效」vs「网络」
- **幂等增量**：再次运行已存在的 server 跳过、仅追加新仓（同步 `.mcp.json` + repo-tracer tools 白名单）；删仓时提示清理对应变量/条目/工具。

## 安全铁律
- 配置文件零明文：`.mcp.json` / agent `.md` / settings **只允许 `${VAR}` 占位**，绝不出现真实 token。
- skill 不持有 token 明文；提醒用户勿提交含真实 token 的临时脚本。
