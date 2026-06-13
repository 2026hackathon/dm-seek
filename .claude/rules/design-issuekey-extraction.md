# 设计预备 — repo-tracer commit 工单号抽取规格（边界用例）

| 项目 | 内容 |
| --- | --- |
| 文档 | design-issuekey-extraction.md（T12 设计预备 / 抽号契约） |
| owner | tools-dev |
| 用途 | 固化 repo-tracer「从 commit subject 抽 Jira 工单号」的规则与边界用例，供 T12 实现 + T16 验证取样；形态/骨架无关 |
| 依据 | T2 实地核验（`design-core-ng-recognition.md` §6 字段化 YAML 规则载体，为权威）+ qa-engineer commit 实况（记忆 hdr-delivery-coreng-markers.md）。**注**：PRD O3 原写「冒号分隔」不准确，已据 T2 实地 git log 更正为「冒号或空白」两种分隔符并存。 |
| 状态 | 设计期参考（T12 实现期采纳；当前不进入实现）。**正则口径以 T2 的 design-core-ng-recognition.md §6 为准，本文与之对齐。** |

> 本文只规格化「抽号」这一纯逻辑，不含 agent 配置/独占（那在 design-mcp-config-shape.md）。抽号是 repo-tracer 的内部职责，与运行形态无关。

---

## 1. 规则

- **默认正则（T2 定稿）**：`^([A-Z]+-\d+)[:\s]` —— **行首工单号 + 冒号或空白分隔**。⚠️ 关键：**冒号式与空格式两种分隔符都存在**（T2 实地 git log 核验），不能只匹配冒号，否则漏掉大批空格分隔提交。
- **本仓特化**：`^(DELI-\d+)[:\s]`（可配置；默认 `^([A-Z]+-\d+)[:\s]` 兜底其他仓库的不同项目键）。
- **位置约定**：工单号位于 **commit subject 行首**，其后紧跟**冒号 `:` 或空白 `\s`**（空格/制表），再接描述：`<KEY>:<描述>` 或 `<KEY> <描述>`。
- **可配置**：正则做成配置项（默认上式），支持多项目键（如同时识别 `DELI-`/`PLAT-`）。
- **容错无号提交**：subject 无匹配时，**不报错**，标记该 commit 为「无工单号」（仍纳入时间线，仅缺 Jira 关联这一环——呼应 PRD 置信度「缺 jira=中」）。
- **Revert 二次抽号（T2 裁定为默认行为）**：subject 形如 `Revert "<原 subject>"` 时，**默认穿透 Revert 包裹、抽出被回滚的工单号，并标 `isRevert=true`**（T1 字段名；支撑功能蒸发场景7）。
- **多号容错**：subject 含多个匹配时全部抽出（少见，但 merge/批量提交可能出现），去重保序。

---

## 2. 边界用例表（据 hdr-delivery-project 真实 commit）

| # | commit subject 样例 | 期望抽取 | 说明 |
| --- | --- | --- | --- |
| 1 | `DELI-4520:Fixed xxx` | `["DELI-4520"]`, isRevert=false | **冒号式**（实地坐实） |
| 2 | `DELI-4512 Non-test source...` | `["DELI-4512"]`, isRevert=false | **空格式（实地坐实，T2 新增）**：行首工单号 + 空格分隔；旧版只匹配冒号会漏掉 |
| 3 | `DELI-4489 Parallel...` | `["DELI-4489"]`, isRevert=false | **空格式（实地坐实，T2 新增）** |
| 4 | `update external api version` | `[]`, isRevert=false（无号） | **容错无号分支**：纳入时间线、标 noTicket，不报错 |
| 5 | `Revert "DELI-4520:Fixed xxx"` | `["DELI-4520"]`, **isRevert=true** | **Revert 穿透（默认行为）**：穿透 `Revert "..."` 抽被回滚工单号 + 标 isRevert=true；对应场景7「功能蒸发追踪」 |
| 6 | `Revert "DELI-4489 Parallel..."` | `["DELI-4489"]`, **isRevert=true** | Revert 包裹内是**空格式**也要能抽（穿透后仍用 `^([A-Z]+-\d+)[:\s]`） |
| 7 | `DELI-4511:upgrade coreNG to 5.0.4` | `["DELI-4511"]`, isRevert=false | 框架版本变更亦可定位 |
| 8 | `DELI-100:a ... DELI-101 b`（同 subject 多号，假想） | `["DELI-100","DELI-101"]` | 多号去重保序（两种分隔符混合也覆盖） |
| 9 | `deli-4520: lowercase`（小写键，假想） | `[]` 或按配置 | 默认 `[A-Z]+` 不匹配小写；若仓库存在小写习惯，由可配置正则覆盖（以代码实际为准） |
| 10 | `Merge branch 'x' into y`（merge commit，假想） | `[]`, isRevert=false（无号） | merge 提交常无号，走容错分支 |

> **空格式（#2/#3，T2 实地核验新增）是本次修正重点**：分隔符 `[:\s]` 容冒号与空白两种，旧版只匹配冒号会系统性漏掉空格分隔的一大批提交。
> **Revert 用例（#5/#6）**：穿透 `Revert "<原 subject>"` 抽**被回滚的工单号** + 标 `isRevert=true`（T2 裁定为默认行为），供 synthesizer 做功能蒸发/回归分析（场景 6/7）；注意被包裹的原 subject 可能是空格式，穿透后仍按 `^([A-Z]+-\d+)[:\s]` 抽。

---

## 3. 输出契约（字段名以 T1 §2.4 为权威，本文对齐）

> **字段名口径（critic B4/B1 收口，T1 字段名已锁定 2026-06-12）**：以 `design-agent-io-schema-reference.md`（T1）§2.4 为权威，三字段锁定为：`ticketIds`(array<string>, **必填**) / `noTicket`(boolean, 可选) / `isRevert`(boolean, 可选)。本文原用的 `issueKeys`/`hasIssueKey`/`revert` 已统一为 T1 名，类型/必填性与 T1 一致。

每个 commit 抽号产出结构：

```
{
  sha: <commit-sha>,
  subject: <原始 subject>,
  ticketIds: ["DELI-4520", ...],   // array<string>, 必填；可空数组=无工单号；冒号式/空格式统一抽到此（T1 §2.4）
  noTicket: <bool>,                // boolean, 可选；= ticketIds 为空；容错标记，缺 jira 关联时置信度降级依据（T1 §2.4）
  isRevert: <bool>,                // boolean, 可选；Revert 提交标记，默认穿透抽出被 revert 原工单号填 ticketIds 并置 true（T1 §2.4）
  repo: <repoSlug>                 // 多仓路由用
}
```

---

## 4. 对下游

- **T12 repo-tracer 实现**：按 §1 规则 + §2 用例实现抽号；正则可配置；Revert 穿透标 `isRevert`；无号容错置 `noTicket`。
- **T16 验证**：§2 的真实样例（#1/#2/#5 来自 hdr-delivery-project 实况，含冒号式/空格式/Revert）作为端到端取样点。
- **置信度联动**：`noTicket=true` 的 commit → 该结论缺 Jira 业务原因一环 → evidence-verifier 据此给「中」（PRD O4）。
