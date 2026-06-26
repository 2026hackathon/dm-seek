---
name: git-analysis
description: Git 时间线 + 工单号 + 跨仓验证。供 code-analyst 调用，不发送消息、不持有 MCP。
---

# git-analysis

> 仅被 code-analyst 通过 Skill 工具调用，不发送 SendMessage、不调 mcp__*、不读写 KB vault。仅使用 Bash 本地 git 命令。

## 0. 何时调用

- 每完成一个代码叙事单元后
- normal/deep 深度下，每个 batch 打包前调用一次
- shallow 深度不调用（不碰 git）

调用前 code-analyst 确认 localPath 存在（Read .claude/repos.json）。

## 1. Part A — Git 时间线提取

### 输入
`repoSlug, localPath, branch, maxCount[=50], since[可选]`

### 执行
`git -C <localPath> log --format="%H|%s|%ai|%an" -n <maxCount> [--since <since>]`
多仓时逐仓执行，按 repoSlug 分组返回。

### 容错
| 场景 | 处理 |
|------|------|
| localPath 不存在 | error: "local_path_missing"，不崩溃 |
| git 命令失败 | error: "git_command_failed" + stderr |
| 空历史 | commits: []，不报错 |
| 无本地仓库（纯远端） | staleness: "no_local"，code-analyst 经 git-tracer 取 |

### 输出
```yaml
timeline:
  - repoSlug, staleness: ok|no_local|unknown
    commits: [{sha, subject, date(ISO8601), author, touchedPaths[]}]
```

## 2. Part B — 工单号抽取

### 输入
Part A commit 列表的 subject 字段。

### 正则
默认 `^([A-Z]+-\d+)[:\s]`，可配置多项目键（如 `^((?:DELI|HDR)-\d+)[:\s]`）。

### Revert 穿透
`Revert "<原 subject>"` → 穿透引号内层，对原 subject 二次抽号。标记 isRevert: true，支持嵌套。

### 容错
| 场景 | 处理 |
|------|------|
| 无匹配 | ticketIds: [], noTicket: true |
| subject 为空 | 跳过该 commit |
| Revert 无引号 | 模糊匹配，失败归入 noTicketCommits |

### 输出
```yaml
tickets:
  extracted: [{key, fromCommit, isRevert}]
  byCommit: {"<sha>": [ticketKey]}
  noTicketCommits: [{sha, subject}]
```

## 3. Part C — 跨仓 Commit 验证

### 前置条件
reposInvolved 含多仓且 .claude/dependency-graph.json 可读（缺失则跳过）。

### 流程
1. 筛选 fromRepo/toRepo 均在 reposInvolved 中的边
2. 逐边验证：`git log --grep "<artifact>"` + publish.json 变更 commits（`git show` 提取版本号）→ 交叉时间线对比
3. 匹配分级：commit_message（强）> static_only（中）> timestamp_correlation（弱）
4. 无 localPath → 放入 unverifiedStaticDeps，交 code-analyst 经 git-tracer 远端验证

### 输入/输出
```yaml
# 输入
reposInvolved: [{slug, localPath, viaArtifact?}]
dependencyGraph: {edges: [{fromRepo, toRepo, viaArtifact, versionConsumed, versionExported, versionMatch}]}

# 输出
crossRepoEvidence: [{fromRepo, fromSha, toRepo, toSha, viaArtifact, versionConsumed, versionExported,
                     evidence: "commit_message"|"static_only"|"timestamp_correlation",
                     direction: "consumer_driven"|"producer_driven"|"unknown",
                     matchMethod: "artifact_grep"|"version_grep"|"timestamp_only"}]
unverifiedStaticDeps: [{fromRepo, toRepo, viaArtifact, reason}]
error: string|null
```

## 4. 调用示例

```
Skill("git-analysis", {
  repoSlug: "hdr-delivery-project",
  localPath: "/d/dev/hdr-delivery-project",
  branch: "develop",
  maxCount: 50,
  since: null,
  reposInvolved: [...],
  dependencyGraph: {...}
})
```
