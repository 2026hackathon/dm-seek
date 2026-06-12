---
name: setup-guide
description: 马冬梅计划开箱引导/配置——带用户完成 MCP 凭据配置(Jira/GitHub 多仓)、探测本地多仓与 obsidian CLI、生成跨 Windows/macOS 的环境变量设置命令。凭据一律环境变量 ${VAR} 引用、绝不明文落配置。当用户首次导入配置包、或新增仓库/凭据时使用。
---

# setup-guide — 开箱引导 / 配置（跨 Win/macOS）

> 依据 `docs/design-mcp-config-shape.md`（路径 B：共享 `.mcp.json` + tools 白名单 + 声明区块 + 凭据 ${VAR} 化）+ `docs/design-jira-mcp-toolmap.md`（Jira env）。**探测非敏感项 + 引导手填敏感项**——skill 全程不接收、不存储任何 token 明文。

## 何时用
- 首次导入 dm-seek 配置包；或新增 git 仓库 / 补配凭据 / 配置 Jira。

## 探测/手填界线（硬性）
- **可自动探测（非敏感）**：本地仓库路径、`git remote get-url origin` 推断的 repoSlug、平台与默认 shell、obsidian CLI 二进制位置、vault 路径。
- **必须用户手填（敏感）**：所有 token / 邮箱——由用户粘贴到自己终端执行，skill 不接收明文。

## 步骤

### 1. 探测多仓（非敏感、自动）
扫描用户指定目录，发现 `.git` → `git remote get-url origin` 推断 repoSlug（小写、非 `[a-z0-9-]`→`-`）→ 机械生成：
- MCP server 名 `github-<repoSlug>`；token 变量名 `DMSEEK_GH_TOKEN_<REPO_SLUG_UPPER>`（大写、`-`→`_`）。
- 维护「仓↔实例↔token 变量」映射表（`docs/design-mcp-config-shape.md` §2.3）。

### 2. 写共享 `.mcp.json`（路径 B）
把 GitHub 多仓（每仓一 `github-<repoSlug>` http 条目，端点 `${DMSEEK_GH_MCP_URL:-https://api.githubcopilot.com/mcp/}`、`Authorization: Bearer ${DMSEEK_GH_TOKEN_<...>}`）+ Jira（stdio，`@aashari/mcp-server-atlassian-jira`，env `ATLASSIAN_*=${DMSEEK_JIRA_*}`）写入项目根 `.mcp.json`。模板见 `docs/templates/mcp-servers.shared.placeholder.jsonc`。
**同步**：把对应 `mcp__github-<repoSlug>__*` 追加进 **repo-tracer 的 `tools` 白名单**（独占承重点；模板 `docs/templates/agent-tools-allowlist.placeholder.md`）。

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
变量清单见 `docs/design-mcp-config-shape.md` §4.2。**提醒：设完变量需重启 Claude Code / 终端**，`${VAR}` 才展开。

### 4. obsidian CLI 路径探测与注入
- 探测二进制（Windows `D:\obsidian\Obsidian.com`、macOS 名不同/无 `.com` 后缀），设 `${DMSEEK_OBSIDIAN_CLI}` 供 kb-keeper 使用。CLI 不在 PATH，须显式路径。
- **C10 — vault 根选址校验（硬性）**：探测/确认 vault 路径时，若 **vault 根目录或其路径任一父段以 `.` 开头**（如 `~/.obsidian-vault/`、`/home/u/.kb/...`）→ **提示用户该路径 obsidian CLI 不可读（整 vault 瘫痪）、请改用非 dot 路径**。（把 dot 不可读约束从「目录命名」延伸到「路径选址」。）

### 5. 连通性自检 + 增量
- 提示用户在 Claude Code 内用 `/mcp` 查看各实例连接状态；失败时区分「token 未设/无效」与「网络」。
- **幂等增量**：再次运行已存在的 server 跳过、仅追加新仓（同步 `.mcp.json` + repo-tracer tools 白名单）；删仓时提示清理对应变量/条目/工具。

## 安全铁律
- 配置文件零明文：`.mcp.json` / agent `.md` / settings **只允许 `${VAR}` 占位**，绝不出现真实 token。
- skill 不持有 token 明文；提醒用户勿提交含真实 token 的临时脚本。
