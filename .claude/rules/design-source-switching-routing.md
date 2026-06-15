# 双源切换 + 多仓路由 + 过时判定

> 代码来源双源（本地/远端）切换、按「被检索到的相关代码」粒度的过时判定（非整仓比较）、多仓路由协调。MCP 实例配置形态见 `design-mcp-config-shape.md`，本文只定义**路由与判定的流程语义**。

---

## 0. 范围与边界

- **管什么**：一次查询命中的代码，来源走本地还是远端 GitHub MCP；远端版本是否比本地新、何时就此询问用户；一次查询横跨多仓时如何把每段代码路由到对的仓库/实例。
- **不管什么**：远端 MCP server 注册/认证/独占机制（→ `design-mcp-config-shape.md`）；工单号抽取（→ `design-core-ng-recognition.md` §5）；返工循环（→ `design-agent-io-schema-reference.md` §7）。
- **铁律**：过时判定**按被检索到的相关代码段粒度**，**绝不做整仓 diff / 整仓 fetch 比较**。

---

## 1. 三态切换总表（逐仓判定）

判定单元是 **(仓库, 相关代码段)** 对，不是整仓。每个被 code-analyst 定位到的 location 独立判定其来源状态。

| # | 本地仓库状态（针对**该相关代码段**所在仓库） | 来源行为 | code-analyst 取码途径 |
| --- | --- | --- | --- |
| A | **无该仓本地副本** | **远端模式**：全程经 repo-tracer 走 GitHub MCP 取代码与历史 | `code_fetch_request`（§2.3.1）→ repo-tracer |
| B | **有本地仓，且该代码段不过时**（远端未比本地新，或离线/无远端可比） | **用本地**：code-analyst 直读本地文件**及本地 git 历史** | 代码内容直读本地路径，不触发 fetch；**本地 git 历史经 `Bash`（`git -C <repoPath> log`）直读**，随 `code_location_set.localGitTimeline` 附给 repo-tracer，repo-tracer 信任采用、统一收口产出 `repo_timeline`（抽工单号仍归 repo-tracer；未附则 repo-tracer 自取兜底） |
| C | **有本地仓，但该代码段远端版本更新** | **就该段询问用户**是否取远端最新（**非整仓比较**） | 用户同意 → `code_fetch_request` 取该段最新；拒绝 → 用本地并在报告标注 |

> 三态以**仓库**为粒度选择「有无本地」，以**代码段**为粒度判定「过时与否」。即同一仓库内，A/B 由该仓是否存在本地副本决定；B vs C 由具体被检索代码段的新旧决定。一次查询的不同 location 可分别落入不同态。

---

## 2. 过时判定：粒度界定与实现

### 2.1 「相关代码段」如何界定

「相关代码段」= code-analyst 本轮定位产出的 `code_location_set.locations[]` 中**每一个 location**，其粒度为：

- 最小落到 **文件 + 行范围**（`filePath` + `lineRange`，见契约 §2.3）；
- 判定与取码以**文件**为最小实际操作单位（行范围用于解读聚焦与报告标注，version 比对落到文件 blob）。

理由：core-ng 识别（`design-core-ng-recognition.md`）定位的入口/调用链节点天然是「类/文件」级；以文件为比对单位既精准又可机械实现（git blob / GitHub contents API 都按文件给 sha），避免整仓比较。

### 2.2 比对远端版本的实现（repo-tracer 执行）

判定「该文件远端是否比本地新」，repo-tracer 在收到 code-analyst 对某 location 的来源探测请求时，对**该文件**执行：

1. **本地侧**：取本地该文件在当前分支的最新提交 sha（等价 `git log -1 --format=%H -- <filePath>`）与 blob hash。
2. **远端侧**：经 GitHub 官方 Plugin（server `github`，`mcp__github__get_file_contents` / `mcp__github__list_commits`）取远端默认分支（或用户指定分支）**该文件**的最新 commit sha / blob sha。
3. **比对**：
   - 本地 == 远端 → `staleness = fresh`（态 B）。
   - 本地存在但远端更新（远端有本地没有的、触碰该文件的更晚 commit）→ `staleness = stale`（态 C）。
   - 本地无该仓 → `staleness = no_local`（态 A）。
   - 无远端可比（离线 / 未配置该仓 MCP / API 失败）→ `staleness = fresh` 降级处理（用本地）+ 在 `code_fetch_response.notes` 标注「未能比对远端」，由 verifier 视作置信度风险点（见 §5）。

> **不做整仓比较**：每次只对被检索到的若干文件按 path 查询远端，请求量 = 相关 location 数，与仓库规模无关。

### 2.3 比对触发时机

- 仅当 **本地存在该仓副本** 且 code-analyst 判断该 location 与结论强相关（`needRemoteFetch` 倾向）时才发起远端比对——避免对每个无关文件都打远端。
- 态 A（无本地）不需比对，直接远端取码。
- 默认分支取该仓 `git remote` 默认分支；若 KB 线索/用户指定了分支/tag，按指定。

### 2.4 契约字段对齐（扩展 §2.3.1 code_fetch_response）

与 `design-agent-io-schema-reference.md` §4 一致，明确 `code_fetch_response`（repo-tracer → code-analyst）字段：

```json
{
  "queryId": "q-...", "round": 0,
  "from": "repo-tracer", "to": "code-analyst",
  "payloadType": "code_fetch_response",
  "payload": {
    "results": [
      {
        "repo": "hdr-delivery-project",
        "filePath": "order-service/.../OrderTimeoutPolicy.java",
        "staleness": "stale",
        "localSha": "a1b2c3d",
        "remoteSha": "f9e8d7c",
        "remoteLatestCommit": {"sha": "f9e8d7c", "date": "2026-05-30T...", "subject": "DELI-4700:..."},
        "content": null,
        "notes": "本地落后远端 1 次提交（DELI-4700 触碰该文件）"
      }
    ]
  }
}
```

| 字段 | 取值 | 说明 |
| --- | --- | --- |
| `staleness` | `fresh`/`stale`/`no_local` | §2.2 判定结果 |
| `localSha` / `remoteSha` | string/null | 该文件本地/远端版本锚点；`no_local` 时 localSha=null |
| `remoteLatestCommit` | object/null | 远端更新时附带最新触碰 commit（供用户决策与时间线） |
| `content` | string/null | 仅在「态 A 直接取码」或「态 C 用户确认取最新」时填实际内容；纯比对探测时为 null |
| `notes` | string | 比对说明 / 无法比对的降级标注 |

> 实现选择：探测与取码可一次往返（`stale` 时顺带回 content 供用户确认后即用）或两次往返（先探测、用户确认再取）。**默认两次**（先探测出 staleness，dongmei-ma 询问用户，确认后 repo-tracer 再取 content），避免未授权就拉取；离线/低敏场景可由实现优化为一次。

---

## 3. 用户交互点（态 C 的询问）

态 C 是**唯一**需要打断流程问用户的点。交互归属与契约：

- **谁问**：`dongmei-ma`（用户接口层，唯一对用户）。code-analyst/repo-tracer 不直接问用户，只把 `staleness=stale` 经产物上报 dongmei-ma。
- **问什么**（就该段，逐文件聚合呈现，避免一段一问的打扰）：
  > 检索到的相关代码 `OrderTimeoutPolicy.java`（仓库 hdr-delivery-project）本地版本落后远端 1 次提交（远端最新 `DELI-4700`，2026-05-30）。是否取远端最新版本用于本次分析？[取最新 / 用本地]
- **多段聚合**：一次查询若多个 location 命中 `stale`，dongmei-ma **合并为一次询问**（列出涉及的文件 + 各自落后情况），用户可一次性选「全部取最新 / 全部用本地 / 逐项选择」，减少交互轮次。
- **用户选择的后果**：
  - 取最新 → code-analyst 据 repo-tracer 回的远端 content 重做该段解读；该 location `sourceMode` 标 `remote`，evidence 注明远端 sha。
  - 用本地 → 用本地内容；报告与 verifier 标注「该段使用本地版本，远端有更新（remoteSha）未采纳」，作为置信度提示而非阻断。
- **非交互/批处理模式**（无人值守，如 KB 初始化或 CI）：提供默认策略开关 `staleDefault ∈ {prefer_local, prefer_remote, ask}`，默认 `ask`；批处理设 `prefer_remote` 或 `prefer_local` 时跳过询问并在结果标注所用策略。此开关供 dongmei-ma / 引导 skill 落地。

---

## 4. 多仓路由

### 4.1 路由链路（线索 → 映射 → 实例）

```
kb-keeper(kb_clue_set.clues[].repoHint, 仅参考)
        │
        ▼
code-analyst 定位并权威确定每个 location 的 repo
   → code_location_set.reposInvolved = 去重(locations[].repo)   ← 路由的权威输入
        │
        ▼
repo-tracer 按 reposInvolved 路由：
   每个 repo  ──经 GitHub 官方 Plugin（server `github`）──▶
        ├─ 有本地副本(配置了本地路径)   → 本地 git 操作
        └─ 经 `mcp__github__*` 工具（owner/repo 参数区分仓库）
   一次查询横跨 N 仓 → repo-tracer 对每仓分别取时间线/取码，按 repo 标注合并
        │
        ▼
repo_timeline.reposCovered  应 == reposInvolved（缺仓=漏仓风险，verifier 校验）
```

### 4.2 权威与参考的分工

- **kb-keeper 的 `repoHint` 仅参考**：KB 线索可能给出候选仓库，但 KB 可能过时/不全，**不作路由权威**。
- **code-analyst 的 `locations[].repo` 为权威**：以实际代码定位坐实该段属于哪个仓（按 §1 core-ng 模块布局 + 本地/远端实际命中），汇总成 `reposInvolved`。
- **repo-tracer 据 `reposInvolved` 路由**：有本地副本走本地 git（Bash），远端经 GitHub 官方 Plugin `mcp__github__*` 工具（owner/repo 参数区分仓库）。

### 4.3 跨服务隐性调用的漏仓兜底

一次查询可能因跨服务调用隐性涉及未被首轮定位的仓库（如 A 服务调 B 服务的 WebService client）。处置：

- code-analyst 在解读时若发现 `api().client(XxWebService.class, ...)`（如样本 `DeliveryTaskServiceApp.bindClient()` L390-407 调用其他服务）等**跨服务调用标志**，应把被调服务对应的仓库**补入 `reposInvolved`**。
- repo-tracer 回 `reposCovered`；若 `reposCovered ⊊ reposInvolved`（某仓未配置实例/无本地、取不到）→ 标注缺仓。
- evidence-verifier 比对 `reposInvolved` vs `reposCovered`，缺仓计入 `gaps`（missingSource 关联 git/code），触发 `add_repos` 发散返工（契约 §7.3）扩大仓库范围重定位。

### 4.4 仓库未配置的处理

- 若 code-analyst 定位到某 repo，但既无本地副本、GitHub 官方 Plugin 也未认证（`/mcp` OAuth 未授权或 token 过期）→ repo-tracer 标该仓 `unconfigured`，无法取码/取史。
- dongmei-ma 据此在报告标注「涉及仓库 X 未配置来源，相关证据缺失」，计入缺口；可建议用户 `/plugin install github` + `/mcp` 完成 OAuth 授权。

---

## 5. 对置信度的影响（与 verifier 协同）

下列双源/路由相关情形作为 evidence-verifier 置信度下调或缺口标注的依据（契约 §7.2 附加降级因素）：

| 情形 | 置信度影响 |
| --- | --- |
| 态 C 用户选「用本地」，远端有更新未采纳 | 标注「分析基于本地版本，远端已变更」；不必然降级，但显式声明 |
| 无法比对远端（离线/API 失败，§2.2 降级 fresh） | 标注「未能确认本地是否最新」，置信度谨慎（中），不假装 fresh 为已校验 |
| `reposCovered ⊊ reposInvolved`（漏仓） | 计入 gaps（缺 git/code 源），触发 add_repos 返工；仍不足则降级交付 |
| 涉及 `unconfigured` 仓库 | 该仓证据缺失，明确标注缺口 |

---

## 6. 全流程时序（一次查询，含多仓 + 态 C）

```
1. dongmei-ma 收疑问 → query_plan → kb-keeper
2. kb-keeper → kb_clue_set（repoHint 参考）
3. code-analyst 定位：
     - 本地有的仓：直读；判断相关段是否需远端比对(needRemoteFetch)
     - 本地无的仓(态A)：标 needRemoteFetch=remote
     - 汇总 reposInvolved
     - 对需比对的 location 发探测请求 → repo-tracer
4. repo-tracer 逐文件比对 staleness(§2.2) → code_fetch_response(content=null 探测)
5. 若有 staleness=stale(态C)：
     code-analyst 上报 → dongmei-ma 合并询问用户(§3)
     用户选取最新 → repo-tracer 取 content → code-analyst 重解读
     用户选用本地 → 标注沿用
6. code-analyst 产出 code_location_set(各 location sourceMode 已定) → repo-tracer
7. repo-tracer 按 reposInvolved 逐仓取时间线+抽工单号 → repo_timeline(reposCovered)
8. → jira-tracer → synthesizer → evidence-verifier(校验漏仓/过时标注) → dongmei-ma 交付
```

---
