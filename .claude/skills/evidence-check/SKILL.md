---
name: evidence-check
description: 证据校验 skill——校验 synthesis 中每条结论的出处充分性、置信度、边界违规、缺口标注。由 synthesizer 在 S7 步骤调用。
---

# evidence-check — 证据校验（skill，由 synthesizer 调用）

本 skill 接收 `synthesis` 为输入，产出 `selfVerification`（verdict / confidence / gaps[] / boundaryViolations[] / divergeHints[] / kbNote）。**synthesizer 必须原样嵌入 synthesis.selfVerification，不可改写。**

## 输入

`synthesis`（含 conclusions[]、crossRepo、sourcesPresent）

## 输出

`selfVerification`：`{verdict, confidence, perConclusion[], gaps[], divergeHints[], boundaryViolations[], kbNote?}`

## 校验步骤

### A. 逐结论出处校验（对 `synthesis.conclusions[]` 每条）

1. **出处存在性**：`evidence[]` 非空 → `hasEvidence=true`；空 → `false`、`ok=false`、必入 gaps。
2. **类型记录**：`evidenceTypes` = evidence 中 `type` 去重（code/commit/jira）。
3. **可回挂性抽检**：`ref` 格式合法（`路径#行` / `repo@sha` / 工单号 / `KB路径#行`）；非法视同无效出处。
4. **维度-出处匹配**：`current_state` 应有 code；`timeline` 应有 commit；`root_cause` 应有 jira（无独立 jira 工单时，含充分业务说明的 commit message 可顶，但该结论**置信度封顶为中**）。维度缺对应出处 → `ok=false` 或降级。

### B. 三级置信度判据（runtime-spec §6）

与 runtime-spec §6 保持一致：高=三源闭环+独立 Jira 印证；中=缺 Jira 或 commit message 顶替（封顶中）；低=依赖推断/单源/三源矛盾。附加下调因素：`shallowWarning`；漏仓；`missingTickets`；大量 `noTicket`；态C 用本地；`crossRepoChainBroken`、`unmatchedDependency`。

**红线——KB 偏差不下调置信度**：`code_location_set.kbAlignment.verdict` 为 stale/contradicted/partial 时，仅记 `kbNote`。KB 偏差不等于结论证据不足——不触发 insufficient、不下调 confidence、不进 gaps、不触发返工。

### C. 边界违规校验（self-audit）

对每条结论的 `evidence`，核数据来源与 agent 角色职责（runtime-spec §4.1/§4.3）的一致性：
- `code` → code-analyst；`commit` → code-analyst（本地 git 独占）；`jira` → jira-tracer；`kb` → kb-keeper
- 越界 → `boundaryViolation`，置信度下调 + 缺口标注

### D. 缺口标注 + 发散映射

`gaps[] = {missingSource, whichConclusion, missingLink, detail, suggestedHint}`。
`missingLink` 枚举：`kb_clue`/`code_location`/`code_interpretation`/`git_timeline`/`ticket_extraction`/`jira_reason`/`repo_coverage`/`cross_repo_chain`/`cross_repo_chain_broken`/`missing_repo`。

缺环→hint 映射：kb_clue→widen_kb_search/kb_to_source_fallback；code→expand_code_scope；git_timeline→extend_git_history；jira_reason→chase_linked_tickets/retry_missing_tickets；cross_repo_chain→extend_cross_repo_search；cross_repo_chain_broken→follow_cross_repo_chain；missing_repo→add_repos；不匹配→reframe_synthesis。

### D2. 跨仓证据校验

当 `synthesis.crossRepo` 存在且 `chainSteps` 非空时执行。否则跳过。

- **crossRepoChainComplete**：核 chainSteps 每步是否有 commit 出处。首步缺失同等于 broken。中间断裂 → `cross_repo_chain_broken`，置信度下调一档。
- **dependencyCoverage**：若 `synthesis.crossRepo.unmatchedDeps` 非空 → `gap: missing_repo`。不阻断 verdict，但下调置信度一档。

### E. verdict 与返工边界

- `verdict=sufficient`（高/中）→ dongmei-ma 交付（中需显式标注缺口）
- `verdict=insufficient`（低/关键结论 ok=false）→ synthesizer 产 rework_suggestion
- 跨轮对比 gaps 收敛性，防空转。中可交付但显式标注。

### F. 输出格式

`{verdict, confidence, perConclusion[{statement,hasEvidence,evidenceTypes,ok}], gaps[], divergeHints[], boundaryViolations[], kbNote?}`
