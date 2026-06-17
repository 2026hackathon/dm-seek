---
name: setup-guide
description: 马冬梅计划开箱引导/配置——双轨 GitHub 认证（gh-mcp OAuth 推荐 + 官方 MCP PAT 备选）；Atlassian plugin OAuth；探测本地多仓与 obsidian CLI；凭据零明文。
---

# setup-guide — 开箱引导 / 配置（跨 Win/macOS）

> GitHub 提供两条认证路径，凭据零明文。
>
> **Windows 用户**：可直接运行 `scripts/setup.ps1` 一键初始化（右键 "使用 PowerShell 运行"），自动完成环境探测、认证引导、仓库 Clone、配置生成。macOS 用户继续参照本文手动步骤。

## 何时用
- 首次导入 dm-seek 配置包；或新增 git 仓库 / 补配凭据 / 配置 Jira。
- Windows 用户优先用 `scripts/setup.ps1`，本文为参考手册。

## 探测/手填界线（硬性）
- **可自动探测（非敏感）**：本地仓库路径、`git remote get-url origin` 推断的 repoSlug、平台与默认 shell、obsidian CLI 二进制位置、vault 路径。
- **必须用户手填（敏感）**：所有 token——由用户粘贴到自己终端执行，skill 不接收明文。

---

## 0. GitHub 认证引导（双轨选择）

> dm-seek 提供两条 GitHub 认证路径，互斥二选一。

### 0.0 环境探测与路径推荐

```
├─ 有 gh CLI + 有浏览器 → 路径 A：gh-mcp OAuth（推荐）
├─ 有浏览器 + 无 gh CLI → 引导安装 gh CLI → 路径 A
└─ 无浏览器（headless/CI）→ 路径 B：官方 MCP + PAT
```

---

### 0.1 路径 A：gh-mcp OAuth（推荐，有浏览器）

> 使用 `gh` CLI 扩展 [`shuymn/gh-mcp`](https://github.com/shuymn/gh-mcp)，通过 `gh auth login` 浏览器 OAuth 认证，**无需手动创建 PAT**。扩展内嵌官方 `github-mcp-server` 二进制，自动读取 `gh` 的 OAuth token。

**步骤**：

1. **安装 `gh` CLI**（如已安装跳到步骤 2）
   - Windows（winget）：`winget install --id GitHub.cli`
   - Windows（无 winget）：打开 https://cli.github.com 手动下载
   - macOS：`brew install gh`
   - 验证：`gh --version`

2. **登录 `gh`**
   - 执行 `gh auth login`
   - 选择 GitHub.com → HTTPS → **Login with a web browser**
   - 浏览器自动打开 → 登录 GitHub（支持公司 SSO）→ 完成
   - 验证：`gh auth status`
   - 失败 → 提示检查网络/SSO 后重试

3. **安装 gh-mcp 扩展**
   - 执行 `gh extension install shuymn/gh-mcp`
   - 验证：`gh mcp --help`（确认扩展可用）
   - 失败 → 提示检查 `gh` CLI 版本（需 2.x+）

4. **配置 `.mcp.json`**
   - 在 `mcpServers` 中添加（替换已有的 `github` 条目）：
     ```jsonc
     "github": {
       "command": "gh",
       "args": ["mcp"],
       "env": {
         "GITHUB_READ_ONLY": "1"
       }
     }
     ```
   - `GITHUB_READ_ONLY=1` 确保只读模式

5. **重启 Claude Code**，运行 `/mcp` 确认 `github` server ✅ connected

6. **失败处理**
   - `gh mcp` 命令未找到 → 重新安装扩展：`gh extension install shuymn/gh-mcp`
   - OAuth token 过期 → 重新 `gh auth login`
   - Org repo 无权限 → 确认 `gh auth status` 显示正确的 org 账号
   - 反复失败 → 提示切到路径 B（PAT）

---

### 0.2 路径 B：官方 MCP + PAT（备选，headless/无浏览器）

> 使用官方 GitHub MCP server（`https://api.githubcopilot.com/mcp`），通过手动创建的 PAT 认证。适用于 headless、CI/CD、无法使用浏览器的场景。

**步骤**：

1. **创建 GitHub Personal Access Token**
   - 打开 https://github.com/settings/tokens → **Generate new token (classic)**
   - Note: `dm-seek`
   - Expiration: 按需（建议 90 天或更长）
   - **Scope（最小权限）**：勾选 `repo`（只读）+ `read:org`（组织访问，可选）
   - 点击 Generate → **立即复制**
   - Org repo：在 token 列表中点击 **"Configure SSO"** → 授权对应 org

2. **设置环境变量（防终端历史泄漏）**
   - **skill 不接触 token 明文**
   - Windows：
     ```powershell
     $token = Read-Host -Prompt "请粘贴 GitHub PAT" -MaskInput
     [Environment]::SetEnvironmentVariable("GITHUB_TOKEN", $token, "User")
     ```
     重启终端使变量生效。
   - macOS/Linux：
     ```bash
     read -s -p "请粘贴 GitHub PAT: " token && export GITHUB_TOKEN=$token
     ```

3. **配置 `.mcp.json`**
   - 在 `mcpServers` 中添加（替换已有的 `github` 条目）：
     ```jsonc
     "github": {
       "type": "http",
       "url": "https://api.githubcopilot.com/mcp",
       "headers": {
         "Authorization": "Bearer ${GITHUB_TOKEN}",
         "X-MCP-Readonly": "true"
       }
     }
     ```

4. **重启 Claude Code**，`/mcp` 确认 `github` server ✅ connected

5. **失败处理**
   - 401 → PAT 已过期或被撤销，重新生成
   - 403 → PAT 权限不足或未 SSO 授权 org

---

## 1. Atlassian (Jira) Plugin 引导

1. 引导执行 `/plugin install atlassian@claude-plugins-official`
2. `/mcp` 面板 → Atlassian → Authenticate → 浏览器 OAuth 授权
3. 验证：`mcp__atlassian__search_issues` 可用

---

## 2. 探测多仓（非敏感、自动）

扫描用户指定目录，发现 `.git` → `git remote get-url origin` 推断 repoSlug。

---

## 3. obsidian CLI 路径探测与注入

- 探测二进制（Windows `D:\obsidian\Obsidian.com`），设 `${DMSEEK_OBSIDIAN_CLI}`
- **vault 根选址校验**：路径若以 `.` 开头 → 提示改用非 dot 路径

---

## 4. 连通性自检

- GitHub：`/mcp` 确认 `github` server ✅ connected
- Jira：`mcp__atlassian__search_issues`

---

## 5. 仓库范围配置（`.claude/repos.json`）

dm-seek 通过 `.claude/repos.json` 定义分析的仓库范围。每个仓库以 `repoSlug` 为唯一标识。

### 5.1 配置骨架

```jsonc
{
  "repos": {
    "<repoSlug>": {
      "local": {
        "path": "<绝对路径>"
      },
      "remote": {
        "owner": "<org/user>",
        "repo": "<repo>",
        "branch": "<default-branch>"
      }
    }
  }
}
```

| 字段 | 必填 | 说明 |
|------|------|------|
| `local` | 否 | 本地仓库；纯远端仓库可省略整个 `local` 块。路径 B 会自动 clone 到 `dm_repos/<repoSlug>/` 并填充此字段 |
| `local.path` | 否 | 本地仓库绝对路径（路径 A 为已有 clone 路径；路径 B 为 `dm_repos/<repoSlug>/` 的绝对路径） |
| `remote` | 是 | 远端 GitHub 仓库信息 |
| `remote.owner` | 是 | GitHub 组织或用户名 |
| `remote.repo` | 是 | GitHub 仓库名 |
| `remote.branch` | 是 | 远端默认分支 |

> 同时存在 local 和 remote 时，dm-seek 远端拉取自动使用本地当前分支（`git branch --show-current`）。

### 5.2 添加入口（两条路径）

用户可选择进入路径，也可两条都执行（可重复运行，见 §5.5）：

**路径 A：本地仓库探测**（有本地 clone 时推荐）
1. 询问用户要扫描的目录，递归发现 `.git`
2. 每找到一个仓库：`git remote get-url origin` 提取 `owner/repo`，`git branch --show-current` 获取当前分支
3. 填充 `local.path`（绝对路径）+ `remote.{owner, repo, branch}`
4. 写入 `repos.json`

**路径 B：远端仓库浏览**（无本地仓库，或想补充远端仓库）
1. 通过 GitHub MCP 拉取用户权限范围内的仓库：
   - 有 org：`mcp__github__search_repositories(query="org:<org>")`
   - 个人仓库：`mcp__github__search_repositories(query="user:<username>")`（username 经 `mcp__github__get_authenticated_user` 获取）
2. 列出可访问仓库（owner/repo + description），供用户勾选
3. 对用户选中的每个仓库，询问默认分支（默认 `main`）
4. **Clone 到本地 `dm_repos/`**：
   - 在当前运行目录下创建 `dm_repos/` 目录（如不存在）
   - 对每个选中的仓库执行 `git clone --branch <branch> https://github.com/<owner>/<repo>.git dm_repos/<repoSlug>`
   - 失败处理：权限不足 → 提示检查 GitHub 认证；网络问题 → 提示重试或跳过该仓库
5. **写入 `repos.json`**：对每个 clone 成功的仓库，同时填充 `local.path`（`dm_repos/<repoSlug>` 的绝对路径）+ `remote.{owner, repo, branch}`
6. **后续默认行为**：有 local 仓库后，code-analyst 直读本地代码；远端更新时由 dongmei-ma 询问是否 `git fetch` 拉取最新（runtime-spec §9 过时判定），非自动覆盖

### 5.3 远端仓库发现（GitHub MCP）

```
用户触发路径 B
  → mcp__github__search_repositories(query="org:<org>") 或 list 用户 repos
  → 展示仓库列表（owner/repo + description）
  → 用户勾选目标仓库
  → 逐个确认 branch（默认 main）
  → 写入 repos.json（remote only，slug=repo 名）
```

**前置条件**：GitHub MCP 已连通（§0 / §4 连通性自检通过）。

### 5.4 多仓

每个仓库一个条目，`repoSlug` 唯一。dm-seek 按 `reposInvolved` 在 `repos.json` 中匹配对应条目。本地和远端仓库可并存于同一配置。

### 5.5 重复执行（更新配置）

setup-guide 可重复运行，支持增量更新：

- **新增仓库**：按 §5.2 路径 A 或 B 添加新条目，写入不覆盖已有条目
- **已有仓库补缺**：若 `repoSlug` 已存在但缺字段（如路径 B 已写 `remote`，路径 A 补 `local.path`），仅补充缺失字段，不覆盖已有
- **已有仓库更新**：若需覆盖已填充字段（`remote.branch` / `local.path`），询问用户确认后覆盖
- **移除仓库**：引导用户手动从 `repos.json` 删除对应条目
- **修改后无需重启**：repo-tracer 在 `round` 变更时重新读取 `repos.json`

### 5.6 手动编辑

用户可直接编辑 `.claude/repos.json`，格式见 §5.1 骨架。修改后无需重启。

## 安全铁律

- **路径 A（OAuth）**：token 由 `gh` CLI keyring 管理，零明文配置文件
- **路径 B（PAT）**：token 仅存环境变量，`.mcp.json` 零明文
- **skill 全程不接收、不存储 token 明文**
- **PAT 最小权限**：仅勾选 `repo`（只读）+ `read:org`（按需）
- **终端历史泄漏防范**：Windows `Read-Host -MaskInput`，macOS/Linux `read -s`
