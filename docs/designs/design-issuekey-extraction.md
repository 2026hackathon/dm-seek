# repo-tracer commit 工单号抽取规格

> 固化 repo-tracer「从 commit subject 抽 Jira 工单号」的规则与边界用例。抽号是 repo-tracer 的内部职责，与运行形态无关。

---

## 1. 规则

- **默认正则**：`^([A-Z]+-\d+)[:\s]` —— **行首工单号 + 冒号或空白分隔**。冒号式与空格式两种分隔符都存在，不能只匹配冒号。
- **本仓特化**：`^(DELI-\d+)[:\s]`（可配置；默认 `^([A-Z]+-\d+)[:\s]` 兜底其他仓库的不同项目键）。
- **位置约定**：工单号位于 **commit subject 行首**，其后紧跟**冒号 `:` 或空白 `\s`**（空格/制表），再接描述：`<KEY>:<描述>` 或 `<KEY> <描述>`。
- **可配置**：正则做成配置项（默认上式），支持多项目键（如同时识别 `DELI-`/`PLAT-`）。
- **容错无号提交**：subject 无匹配时，**不报错**，标记该 commit 为「无工单号」（仍纳入时间线，仅缺 Jira 关联这一环）。
- **Revert 二次抽号**：subject 形如 `Revert "<原 subject>"` 时，**默认穿透 Revert 包裹、抽出被回滚的工单号，并标 `isRevert=true`**（支撑功能蒸发场景）。
- **多号容错**：subject 含多个匹配时全部抽出（少见，但 merge/批量提交可能出现），去重保序。

---

## 2. 边界用例表（据 hdr-delivery-project 真实 commit）

| # | commit subject 样例 | 期望抽取 | 说明 |
| --- | --- | --- | --- |
| 1 | `DELI-4520:Fixed xxx` | `["DELI-4520"]`, isRevert=false | **冒号式** |
| 2 | `DELI-4512 Non-test source...` | `["DELI-4512"]`, isRevert=false | **空格式**：行首工单号 + 空格分隔 |
| 3 | `DELI-4489 Parallel...` | `["DELI-4489"]`, isRevert=false | **空格式** |
| 4 | `update external api version` | `[]`, isRevert=false（无号） | **容错无号分支**：纳入时间线、标 noTicket，不报错 |
| 5 | `Revert "DELI-4520:Fixed xxx"` | `["DELI-4520"]`, **isRevert=true** | **Revert 穿透**：穿透 `Revert "..."` 抽被回滚工单号 + 标 isRevert=true；对应功能蒸发追踪场景 |
| 6 | `Revert "DELI-4489 Parallel..."` | `["DELI-4489"]`, **isRevert=true** | Revert 包裹内是**空格式**也要能抽（穿透后仍用 `^([A-Z]+-\d+)[:\s]`） |
| 7 | `DELI-4511:upgrade coreNG to 5.0.4` | `["DELI-4511"]`, isRevert=false | 框架版本变更亦可定位 |
| 8 | `DELI-100:a ... DELI-101 b`（同 subject 多号，假想） | `["DELI-100","DELI-101"]` | 多号去重保序（两种分隔符混合也覆盖） |
| 9 | `deli-4520: lowercase`（小写键，假想） | `[]` 或按配置 | 默认 `[A-Z]+` 不匹配小写；若仓库存在小写习惯，由可配置正则覆盖（以代码实际为准） |
| 10 | `Merge branch 'x' into y`（merge commit，假想） | `[]`, isRevert=false（无号） | merge 提交常无号，走容错分支 |

> 分隔符 `[:\s]` 容冒号与空白两种。Revert 穿透：抽被回滚的工单号 + 标 `isRevert=true`，被包裹的原 subject 可能是空格式，穿透后仍按 `^([A-Z]+-\d+)[:\s]` 抽。

---

## 3. 输出契约

以 `design-agent-io-schema-reference.md` §2.4 为权威，三字段：`ticketIds`(array<string>, **必填**) / `noTicket`(boolean, 可选) / `isRevert`(boolean, 可选)。

每个 commit 抽号产出结构：

```
{
  sha: <commit-sha>,
  subject: <原始 subject>,
  ticketIds: ["DELI-4520", ...],   // array<string>, 必填；可空数组=无工单号
  noTicket: <bool>,                // boolean, 可选；= ticketIds 为空；容错标记，缺 jira 关联时置信度降级依据
  isRevert: <bool>,                // boolean, 可选；Revert 提交标记，穿透抽出被 revert 原工单号填 ticketIds 并置 true
  repo: <repoSlug>                 // 多仓路由用
}
```

---

## 4. 对下游

- **repo-tracer**：按 §1 规则 + §2 用例实现抽号；正则可配置；Revert 穿透标 `isRevert`；无号容错置 `noTicket`。
- **置信度联动**：`noTicket=true` 的 commit → 该结论缺 Jira 业务原因一环 → evidence-verifier 据此给「中」。
