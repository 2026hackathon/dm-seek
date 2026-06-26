---
name: setup-guide
description: dm-seek 开箱引导/配置参考手册——GitHub 双轨认证、repos.json 骨架、故障排查。主入口为初始化脚本，本文为补充参考。
---

# setup-guide — 配置参考手册

> **一键初始化**：运行对应平台的引导脚本，交互式完成全部配置：
> - **Windows**：`.\scripts\windows-setup.ps1`
> - **macOS**：`chmod +x scripts/macos-setup.sh && bash scripts/macos-setup.sh`
>
> 本文为补充参考：配置骨架说明、安全铁律、故障排查。

## 与初始化脚本的分工

| 内容 | 初始化脚本 | 本手册 |
|------|:---------:|:------:|
| 环境探测（git / gh / Obsidian） | 自动 [1] | — |
| GitHub 认证引导（OAuth / PAT） | 交互式菜单 [2] | 概述 + 故障排查 |
| 仓库配置（本地扫描 / 远端浏览 / 分支调整 / 启用/禁用） | 交互式子菜单 [3] | repos.json 骨架说明 + enable 字段 |
| KB Vault 初始化与注册 | 自动 [4] | 故障排查 |
| .mcp.json 生成 | 自动 [5]（认证切换时联动触发） | 双模式示例 |
| 连通性自检 | 自动 [6] | 故障排查 |
| 仓库更新检查（fetch + pull） | 交互式菜单 [7] | — |
| 刷新跨仓依赖图（publish.json + build.gradle.kts → dependency-graph.json） | 交互式菜单 [8] | 跨仓依赖可见性 |
| 自动扫描 dm-repos/dm-kbs | 启动时自动执行 | — |
| 安全铁律 | — | 本文 |
| FAQ / 故障排查 | — | 本文 |

---

## 安全铁律

- **路径 A（OAuth）**：token 由 `gh` CLI keyring 管理，零明文配置文件
- **路径 B（PAT）**：token 仅存环境变量，`.mcp.json` 零明文（`${GITHUB_TOKEN}` 变量引用）
- **skill 全程不接收、不存储 token 明文**
- **PAT 最小权限**：仅勾选 `repo`（只读）+ `read:org`（按需）
- **终端历史泄漏防范**：Windows `Read-Host -AsSecureString`（`windows-setup.ps1` 已内置），macOS/Linux `read -s`

---

## .mcp.json 双模式

初始化脚本会根据认证路径自动生成 `.mcp.json`。手动编辑时参考以下示例：

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
## repos.json 配置骨架

dm-seek 通过 `.claude/repos.json` 定义分析仓库范围。`repoSlug` 为唯一标识。**完整字段 schema 见 runtime-spec §12。**

```jsonc
{
  "repos": {
    "<repoSlug>": {
      "local":  { "path": "<绝对路径>" },
      "remote": { "owner": "<org>", "repo": "<repo>", "branch": "<branch>" },
      "kb":     { "vault": "<vault名>", "path": "<相对路径>" }
    }
  }
}
```

> 同时存在 `local` 和 `remote` 时，远端拉取自动使用本地当前分支。字段详解见 runtime-spec §12。

### 手动编辑

直接编辑 `.claude/repos.json`，格式见上方骨架。修改后无需重启——git-tracer 在 `round` 变更时重新读取。

### 增量更新

初始化脚本可重复运行，支持增量更新。启动时自动扫描 `dm-repos/` 和 `dm-kbs/` 目录，检测已有仓库/vault 并补全 repos.json。新增仓库不覆盖已有条目，已有仓库仅补充缺失字段。

---

## macOS

macOS 用户使用 `scripts/macos-setup.sh` 一键完成初始化，功能与 Windows 脚本完全对标：

```bash
chmod +x scripts/macos-setup.sh
bash scripts/macos-setup.sh
```

提供与 Windows 脚本完全相同的 7 项菜单操作 + 启动自动扫描。依赖 Homebrew（脚本会自动检测并提示安装）。

---

## 跨仓依赖可见性

初始化脚本 [8] `刷新依赖图` 自动遍历已启用仓库，生成跨仓依赖图 `.claude/dependency-graph.json`。实现细节见脚本注释；完整 schema 见 runtime-spec §13。

### repos.json enable 字段

在 `repos.json` 的每个仓库条目中增加 `enable` 布尔字段：

```jsonc
{
  "repos": {
    "my-repo": {
      "local": { "path": "..." },
      "remote": { "owner": "...", "repo": "...", "branch": "main" },
      "enable": true   // 可选，默认 true
    }
  }
}
```

- 默认 `true`。脚本和 agent 在跨仓分析中跳过 `enable=false` 的仓库
- 通过 Phase 3 菜单 `[C] 启用/禁用仓库` 交互式管理
- 用于归档仓库、非活跃项目——保留配置但不参与依赖图

### repos.json manualEdges

在 `repos` 同一顶层添加手动声明的跨仓边，与自动推断为对等关系：

```jsonc
{
  "repos": { ... },
  "manualEdges": [
    {
      "fromRepo": "consumer-repo",
      "toRepo": "producer-repo",
      "viaArtifact": "some-service-interface",
      "reason": "手动声明原因"
    }
  ]
}
```

- `manualEdges` 是**对等伙伴**而非降级逃逸舱口（ADR-001）
- 自动推断不覆盖的场景：publish.json 不规范的仓库、非 Gradle 构建、跨组织依赖
- 生成 dependency-graph.json 时与自动推断合并去重，每条边标记 `source: "auto"|"manual"`

### dependency-graph.json schema

见 `runtime-spec.md §13` 完整 schema 与 agent 读取职责。

---

## 高级功能与补充说明

### CLI 参数（-Phase / -Auto）

**Windows** `windows-setup.ps1` 支持：

```powershell
.\scripts\windows-setup.ps1 -Phase 3       # 直接跳转到 Phase 3（跳过菜单）
.\scripts\windows-setup.ps1 -Auto           # 全量线性执行 Phase 1-6
```

**macOS** `macos-setup.sh` 支持：

```bash
bash scripts/macos-setup.sh -p 3           # 直接跳转到 Phase 3
bash scripts/macos-setup.sh -a             # 全量线性执行 Phase 1-6
```

### 启动自动扫描

脚本启动时自动扫描 `dm-repos/` 和 `dm-kbs/` 目录：

- 发现 `dm-repos/` 下未在 `repos.json` 登记的 git 仓库 → 自动添加（补全本地路径 + 远端信息）
- 在 `dm-kbs/` 中发现新 vault 目录（`{slug}_kb`）→ 自动关联到对应仓库条目的 `kb` 字段
- 已登记的仓库不覆盖、仅补充缺失字段

### 分支切换与调整

Phase 3 菜单 [A] 调整仓库分支：

1. 从 `repos.json` 列出所有已配置仓库
2. 选择仓库 → 脚本从远端拉取分支列表
3. 选择分支编号 → 自动切换本地仓库（若非当前分支则 `fetch` + `checkout`）
4. 不支持自动拉取时，允许手动输入分支名

### 远端仓库浏览与 Clone

Phase 3 菜单 [B] → 选择远端浏览：

1. 输入 GitHub org 名（回车=个人）
2. 搜索结果显示分页列表（名称 + 描述），每页 15 条
3. 操作：编号 Clone / 搜索关键词 / 翻页 / 完成
4. Clone 后提示选择分支
5. PAT 模式使用 credential helper 避免 PAT 泄漏到进程列表（Windows 特有）

### .dmseek-init 标记文件

KB vault 初始化后在 `.obsidian/.dmseek-init` 写入标记文件，内容为脚本名 + 时间戳。标记文件存在 → 跳过 vault 初始化（防重复创建）。

### Obsidian Vault 自动注册

Phase 4 初始化 KB vault 时，自动将每个 vault 注册到 Obsidian 配置文件：

- **Windows**：`%APPDATA%\obsidian\obsidian.json` → 生成 UUID 并写入 vault 路径
- **macOS**：`~/Library/Application Support/obsidian/obsidian.json` → 相同逻辑

注册后 Obsidian 启动时自动识别所有 vault。

### DMSEEK_OBSIDIAN_CLI 环境变量

脚本在 Phase 6 自动探测 Obsidian CLI 路径并写入用户级环境变量：

- **Windows**：`setx DMSEEK_OBSIDIAN_CLI <路径>`（用户级，持久化）
- **macOS**：追加 `export DMSEEK_OBSIDIAN_CLI="<路径>"` 到 `.zshrc` / `.bash_profile`

`DMSEEK_OBSIDIAN_CLI` 优先于其他探测路径（默认搜索顺序：环境变量 → 常见安装路径）。

---

## 故障排查

### GitHub MCP 未连接

| 症状 | 可能原因 | 解决 |
|------|---------|------|
| `/mcp` 中 github server 不显示 | .mcp.json 未配置 | 运行 初始化脚本 [5] |
| 路径 A：`gh mcp` 命令未找到 | gh-mcp 扩展未安装 | `gh extension install shuymn/gh-mcp` |
| 路径 A：OAuth token 过期 | gh 认证过期 | `gh auth login` 重新登录 |
| 路径 B：401 Unauthorized | PAT 过期或被撤销 | 重新创建 PAT 并更新 `GITHUB_TOKEN` 环境变量 |
| 路径 B：403 Forbidden | PAT 权限不足或未 SSO 授权 | 检查 PAT scope（需 `repo`），在 GitHub 设置中授权 org SSO |

### repos.json 问题

| 症状 | 可能原因 | 解决 |
|------|---------|------|
| Agent 启动报 "repos.json 为空" | 未运行仓库配置 | 运行 初始化脚本 [3] |
| JSON 解析失败 | 格式错误 | 检查 JSON 语法（逗号、引号配对），可参考上方骨架 |
| 仓库找不到 | slug 或路径错误 | 确认 `repoSlug` 唯一、`local.path` 绝对路径存在 |

### KB Vault 问题

| 症状 | 可能原因 | 解决 |
|------|---------|------|
| kb-keeper 报 "KB 未就绪" | repos.json 无 `kb` 字段 | 运行 初始化脚本 [4] |
| Obsidian CLI 未找到 | 环境变量未设 | 初始化脚本 Phase 6 自动设置；macOS 手动设 `DMSEEK_OBSIDIAN_CLI` |
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
