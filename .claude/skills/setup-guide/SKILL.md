---
name: setup-guide
description: 马冬梅计划开箱引导/配置参考手册——GitHub 双轨认证、repos.json 骨架、故障排查。Windows 用户主入口为 scripts/setup.ps1，本文为补充参考。
---

# setup-guide — 配置参考手册

> **Windows 用户**：主入口是 `scripts/setup.ps1`（交互式分步菜单，按需选择操作）。本文为补充参考：配置骨架说明、安全铁律、故障排查、macOS 手动步骤。

## 与 setup.ps1 的分工

| 内容 | setup.ps1 | 本手册 |
|------|:---------:|:------:|
| 环境探测（git / gh / Obsidian） | 自动 | — |
| GitHub 认证引导（OAuth / PAT） | 交互式菜单 [2] | 概述 + 故障排查 |
| 仓库配置（本地扫描 / 远端浏览） | 交互式子菜单 [3] | repos.json 骨架说明 |
| KB Vault 初始化与注册 | 自动 [4] | 故障排查 |
| .mcp.json 生成 | 自动 [5]（认证切换时联动触发） | 双模式示例 |
| 连通性自检 | 自动 [6] | 故障排查 |
| 安全铁律 | — | 本文 |
| macOS 手动步骤 | — | 本文 |
| FAQ / 故障排查 | — | 本文 |

---

## 安全铁律

- **路径 A（OAuth）**：token 由 `gh` CLI keyring 管理，零明文配置文件
- **路径 B（PAT）**：token 仅存环境变量，`.mcp.json` 零明文（`${GITHUB_TOKEN}` 变量引用）
- **skill 全程不接收、不存储 token 明文**
- **PAT 最小权限**：仅勾选 `repo`（只读）+ `read:org`（按需）
- **终端历史泄漏防范**：Windows `Read-Host -MaskInput`（`setup.ps1` 已内置），macOS/Linux `read -s`

---

## .mcp.json 双模式

setup.ps1 根据认证路径自动生成。手动编辑时参考以下示例：

### 路径 A：gh-mcp OAuth

```jsonc
{
  "mcpServers": {
    "github": {
      "command": "gh",
      "args": ["mcp"],
      "env": {
        "GITHUB_READ_ONLY": "1"
      }
    }
  }
}
```

### 路径 B：Copilot MCP + PAT

```jsonc
{
  "mcpServers": {
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp",
      "headers": {
        "Authorization": "Bearer ${GITHUB_TOKEN}",
        "X-MCP-Readonly": "true"
      }
    }
  }
}
```

> `${GITHUB_TOKEN}` 是变量引用——Claude Code 运行时自动展开为环境变量值，`.mcp.json` 中不留明文。

---

## Jira / Atlassian Plugin

1. 在 Claude Code 中执行：`/plugin install atlassian@claude-plugins-official`
2. `/mcp` → Atlassian → Authenticate → 浏览器 OAuth 授权
3. 验证：`mcp__atlassian__search_issues` 可用

---

## repos.json 配置骨架

dm-seek 通过 `.claude/repos.json` 定义分析仓库范围。`repoSlug` 为唯一标识。

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
      },
      "kb": {
        "vault": "<Obsidian vault 名>",
        "path": "<相对路径>"
      }
    }
  }
}
```

| 字段 | 必填 | 说明 |
|------|------|------|
| `local` | 否 | 本地仓库；纯远端仓库省略整个 `local` 块 |
| `local.path` | 否 | 本地仓库绝对路径 |
| `remote` | **是** | 远端 GitHub 仓库信息 |
| `remote.owner` | 是 | GitHub 组织名或用户名 |
| `remote.repo` | 是 | GitHub 仓库名 |
| `remote.branch` | 是 | 远端默认分支 |
| `kb` | 否 | KB vault 配置，由 setup.ps1 Phase 4 自动写入。无此字段 = KB 未初始化 |
| `kb.vault` | 否 | Obsidian vault 名 |
| `kb.path` | 否 | vault 相对路径（`dm-kbs/<repoSlug>_kb`） |

> 同时存在 `local` 和 `remote` 时，远端拉取自动使用本地当前分支（`git branch --show-current`）。

### 手动编辑

直接编辑 `.claude/repos.json`，格式见上方骨架。修改后无需重启——repo-tracer 在 `round` 变更时重新读取。

### 增量更新

setup.ps1 可重复运行，支持增量更新：新增仓库不覆盖已有条目、已有仓库补缺仅补充缺失字段、覆盖已有字段需用户确认。

---

## macOS 手动步骤

setup.ps1 仅支持 Windows。macOS 用户参照以下最小步骤：

### 1. 安装依赖

```bash
# GitHub CLI
brew install gh

# 登录并安装扩展
gh auth login
gh extension install shuymn/gh-mcp
```

### 2. 配置 .mcp.json

参照上方「.mcp.json 双模式」节。路径 A（OAuth）推荐。

### 3. 配置 repos.json

参照上方「repos.json 配置骨架」节。至少配置 `remote` 块。如需 KB 功能，手动创建 `dm-kbs/<repoSlug>_kb/` 目录并在 Obsidian 中作为 vault 打开。

### 4. 安装 Jira Plugin

```bash
# 在 Claude Code 中执行
/plugin install atlassian@claude-plugins-official
```

### 5. Obsidian CLI（可选，KB 功能需要）

设置环境变量 `DMSEEK_OBSIDIAN_CLI` 指向 Obsidian 二进制文件路径。

---

## 故障排查

### GitHub MCP 未连接

| 症状 | 可能原因 | 解决 |
|------|---------|------|
| `/mcp` 中 github server 不显示 | .mcp.json 未配置 | 运行 setup.ps1 [5] |
| 路径 A：`gh mcp` 命令未找到 | gh-mcp 扩展未安装 | `gh extension install shuymn/gh-mcp` |
| 路径 A：OAuth token 过期 | gh 认证过期 | `gh auth login` 重新登录 |
| 路径 B：401 Unauthorized | PAT 过期或被撤销 | 重新创建 PAT 并更新 `GITHUB_TOKEN` 环境变量 |
| 路径 B：403 Forbidden | PAT 权限不足或未 SSO 授权 | 检查 PAT scope（需 `repo`），在 GitHub 设置中授权 org SSO |

### repos.json 问题

| 症状 | 可能原因 | 解决 |
|------|---------|------|
| Agent 启动报 "repos.json 为空" | 未运行仓库配置 | 运行 setup.ps1 [3] |
| JSON 解析失败 | 格式错误 | 检查 JSON 语法（逗号、引号配对），可参考上方骨架 |
| 仓库找不到 | slug 或路径错误 | 确认 `repoSlug` 唯一、`local.path` 绝对路径存在 |

### KB Vault 问题

| 症状 | 可能原因 | 解决 |
|------|---------|------|
| kb-keeper 报 "KB 未就绪" | repos.json 无 `kb` 字段 | 运行 setup.ps1 [4] |
| Obsidian CLI 未找到 | 环境变量未设 | setup.ps1 Phase 6 自动设置；macOS 手动设 `DMSEEK_OBSIDIAN_CLI` |
| vault 路径以 `.` 开头 | dot-dir Obsidian CLI 不可读 | 改用非 dot 前缀路径（如 `dm-kbs/`） |

### Jira 未认证

| 症状 | 可能原因 | 解决 |
|------|---------|------|
| jira-tracer 报 "Jira 不可用" | OAuth 未完成 | `/mcp` → Atlassian → Authenticate |
| OAuth token 过期 | 缓存失效 | 同上，重新认证即可 |

### 网络问题

| 症状 | 可能原因 | 解决 |
|------|---------|------|
| 远端仓库浏览无结果 | gh 认证失效或网络问题 | 检查 `gh auth status`、代理设置 |
| 仓库 clone 失败 | 权限不足或网络超时 | 检查 PAT scope / SSO 授权，确认网络可达 |
