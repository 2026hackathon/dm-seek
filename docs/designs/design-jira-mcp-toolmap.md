# Jira MCP 工具与端点对照表

> **本文件为历史参考。当前 dm-seek 已纯 Plugin 化（`mcp__atlassian__search_issues` / `mcp__atlassian__get_issue`），不再使用 `@aashari` PAT server。**
>
> 以下内容描述旧方案（`@aashari/mcp-server-atlassian-jira` HTTP 透传型 MCP server）：

该 MCP server **不提供语义化工具**，而是暴露 **5 个通用 HTTP 方法工具**，靠 `path` + 参数访问**任意 Jira Cloud REST API v3 端点**。jira-tracer 必须自己拼 REST 路径。

---

## 1. 暴露的工具（共 5 个，全部为通用 HTTP 方法）

| 工具名（verbatim） | 作用 | 关键参数 |
| --- | --- | --- |
| `jira_get` | 读任意 Jira API 端点 | `path`, `queryParams`, `jq`(JMESPath 过滤), `outputFormat` |
| `jira_post` | 创建资源 | `path`, `body`, ... |
| `jira_put` | 整体替换资源 | `path`, `body`, ... |
| `jira_patch` | 局部更新 | `path`, `body`, ... |
| `jira_delete` | 删除资源 | `path`, ... |

- MCP 工具引用名（在 agent `tools` 白名单 / 权限规则中）：`mcp__jira__jira_get` 等；整服务 `mcp__jira`。
- **jira-tracer 是只读消费者**：实际只需 `jira_get`（取工单/搜索/comments/changelog）。**强烈建议 jira-tracer 的工具白名单仅授予 `mcp__jira__jira_get`**，不授予 post/put/patch/delete——溯源系统只读 Jira，杜绝误写工单。这与「以代码为唯一事实基准、Jira 只读取业务原因」的定位一致。

---

## 2. jira-tracer 需要的端点（Jira Cloud REST API v3，经 `jira_get` 调用）

> jira-tracer 的输入 = repo-tracer 抽出的工单号列表（如 `DELI-4520`）；输出 = 业务原因结构。下表给出取「业务原因 + 因果脉络」所需的端点。

| 目的 | `jira_get` 的 `path` | 关键 queryParams | 取到什么 |
| --- | --- | --- | --- |
| **按工单号取详情**（核心） | `/rest/api/3/issue/{issueIdOrKey}` | `fields=summary,description,issuetype,status,resolution,resolutiondate,parent,issuelinks,created,updated` | 标题、描述（业务原因主体）、类型、状态、解决结果与解决日期（`resolutiondate` → `resolvedDate`）、父子、关联链接 |
| **取变更历史（changelog）** | `/rest/api/3/issue/{issueIdOrKey}` | `expand=changelog` | 字段变更时间线，辅助「为什么变 + 何时变」 |
| **取评论** | `/rest/api/3/issue/{issueIdOrKey}/comment` | `orderBy=created` | 决策讨论、补充业务背景 |
| **JQL 搜索**（多工单/因果脉络） | `/rest/api/3/search/jql` | `jql=...`（如 `issuekey in (DELI-1,DELI-2)` 或按 epic/link 展开） | 批量取、按关系聚合 |
| **取工单的关联关系** | （含于 issue 详情的 `issuelinks` 字段） | 见上 `fields=issuelinks` | blocks/relates/duplicates 等，构建多工单因果脉络 |
| **取项目信息**（可选） | `/rest/api/3/project/{projectKeyOrId}` | — | 项目上下文 |

> **因果脉络**：先对每个工单号 `jira_get` 详情（含 `issuelinks` + `parent`），再按 link 关系 / epic-子任务关系，用 JQL 二次拉取相邻工单，组装成因果图。建库阶段只取「summary + description 概述」级，查询阶段可加 changelog + comments 深挖。
> 可用 `jq`（JMESPath）在 MCP 侧预过滤，减少返回体积（如只取 `fields.summary` 与 `fields.description`）。

### 2.1 `jira_get` 工具 → 输入/输出对照

**工具输入（`mcp__jira__jira_get` 的参数）：**

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `path` | string | 是 | Jira REST v3 端点路径，如 `/rest/api/3/issue/DELI-4520` |
| `queryParams` | object | 否 | 如 `{fields, expand, jql, orderBy}`，见 §2 各端点 |
| `jq` | string | 否 | JMESPath 过滤表达式，MCP 侧预裁剪返回 |
| `outputFormat` | string | 否 | 输出格式 |

**工具输出（MCP 返回）：** Jira REST v3 原始 JSON（经 `jq`/`fields` 裁剪后）。jira-tracer 须把它**归一为业务原因结构**喂给 synthesizer：

```json
{
  "issueKey": "DELI-4520",
  "summary": "...",                 // ← REST fields.summary
  "businessReason": "...",          // ← REST fields.description（业务原因主体）
  "issuetype": "Bug|Story|...",     // ← fields.issuetype.name
  "status": "...", "resolution": "...",
  "resolvedDate": "...|null",       // ← fields.resolutiondate
  "parent": "DELI-xxxx|null",       // ← fields.parent.key
  "links": [{"type":"blocks|relates|...","key":"DELI-yyyy"}],  // ← fields.issuelinks 归一
  "changelogDigest": "...|null",    // ← expand=changelog 摘要（查询期才取）
  "commentsDigest": "...|null",     // ← /comment 摘要（查询期才取）
  "fetchedVia": "jira_get /rest/api/3/issue/DELI-4520"  // 出处可回挂
}
```

> 关键：jira-tracer **不直接把 REST 原始 JSON 透传**给下游，而是归一为上表结构。`businessReason` = `description`（建库期取概述级、查询期取全文）。`fetchedVia` 保留以满足「结论可回挂出处」。多工单时输出数组 + 按 `links`/`parent` 组装的因果脉络。

---

## 3. 运行与凭据

- **运行命令**：`npx -y @aashari/mcp-server-atlassian-jira`（stdio）。
- **必需环境变量**：

| 变量 | 含义 | dm-seek 注入占位 |
| --- | --- | --- |
| `ATLASSIAN_SITE_NAME` | 站点子域（`mycompany.atlassian.net` 取 `mycompany`） | `${DMSEEK_JIRA_SITE_NAME}` |
| `ATLASSIAN_USER_EMAIL` | Atlassian 账号邮箱 | `${DMSEEK_JIRA_EMAIL}` |
| `ATLASSIAN_API_TOKEN` | API Token（id.atlassian.com 生成） | `${DMSEEK_JIRA_API_TOKEN}` |
| `DEBUG`（可选） | `true` 开调试日志 | 默认不设 |

### jira 实例配置落点

Jira MCP 实例写在**共享 `.mcp.json`**。独占靠 **jira-tracer 的 `tools` 白名单仅含 `mcp__jira__jira_get`（只读）**，其余 agent tools 不含任何 `mcp__jira*`。

---

## 4. 对下游

1. **I/O schema**：jira-tracer 的业务原因结构字段 = `{issueKey, summary, description(业务原因主体), issuetype, status, resolution, resolvedDate, parent, links[], changelog摘要?, comments摘要?}`。
2. **jira-tracer 实现**：以 `jira_get` + REST v3 path 为唯一手段；只读授权；容错（工单不存在 / 无权限 / 工单号格式无效）。
3. **建库**：jira-tracer 在建库阶段取「summary + description 概述」级即可。
4. **职责边界**：该 server 无 commits/PR/dev-info 专用工具。Git/commit/PR 信息一律走 repo-tracer 的 GitHub MCP，**不要从 Jira MCP 取 commit**。

---

## 5. 备注

- 本 server 是「通用 HTTP 透传」型 MCP，jira-tracer 的 system prompt 需内置 §2 端点表作为操作手册。
- 真实端点行为建议在实现早期用一个真实工单做连通验证后定稿分页/字段策略。
