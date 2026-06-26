---
name: synthesis-core
description: 三源综合分析方法库（六步骨架+9场景method）——synthesizer 的运行时分析方法来源。
---

# synthesis-core — 综合分析方法库（六步骨架 + 9 场景 method）

> 本 skill 是 synthesizer 分析方法的**单一权威载体**。所有 9 类场景共享**通用六步骨架**，差异只在「侧重维度」与「特化步骤」。**单 skill 多 method**：9 个场景方法以 method 片段收于本 skill 场景库（§2），避免碎片化。

## 何时用

synthesizer 收齐三源（code-analyst `code_location_set` + `repo_timeline` + jira-tracer `jira_reasons`），综合出结论时。据 `query_plan.intent`/`scenario` 选 method（§2）；intent 未明或跨场景 → 通用六步（`synthesis-core-generic-v1`）。

## 0. 硬约束（贯穿全流程，runtime-spec §1）

- **以代码为唯一事实基准**：三源冲突时按代码事实陈述，冲突另一方记为「记录与实现的偏差」。
- **每条结论必须挂出处**（`evidence[]`，code/commit/jira）；无出处 → 入 `unknowns`，不冒充结论、不空想补源（补源靠返工循环，不在本环节）。
- 缺的维度进 `unknowns`，由 S7 evidence-check 判置信度。

## 1. 通用六步骨架（`synthesis-core`，每次综合恒定执行）

| 步 | 名称 | 动作 | 产出落点（契约 §2.7） |
| --- | --- | --- | --- |
| S1 | 三源对齐 | 把 `code_location_set` / `repo_timeline` / `jira_reasons` 按 **代码实体 ↔ commit ↔ 工单** 三方关联对齐，**以代码实体为锚**（runtime-spec §1）。逐 location 找触碰它的 commit（按 `touchedPaths`），逐 commit 找其 `ticketIds` 对应的 jira 业务原因。 | `sourcesPresent{code,git,jira}` |
| S2 | 时间线编织 | 按 commit `date` 排出演变序列，每节点挂 `工单号 + 业务原因`，标 `primary`/`context`；Revert/删除节点显式标注。 | `timelineNarrative` |
| S3 | 结论生成 | 按场景侧重维度（§2）生成 `conclusions[]`，每条限定 `dimension ∈ {current_state, timeline, root_cause}`。 | `conclusions[].statement/dimension` |
| S4 | 出处挂接 | 每条结论强制挂 `evidence[]`（code/commit/jira）；无出处的判断**移入 `unknowns`** 而非冒充结论。维度-出处对应：current_state→code、timeline→commit、root_cause→jira（或含业务说明的 commit message）。 | `conclusions[].evidence` / `unknowns` |
| S5 | 矛盾标记 | 标记三源互相冲突处（代码现状 vs 工单描述不符——正是「马冬梅」要解的认知偏差）；冲突以**代码为准**陈述，记录冲突另一方为偏差，写入对应 conclusion + `unknowns`。 | conclusion + unknowns |
| S6 | 自检交棒 | 填 `analysisMethod`（method id）、`sourcesPresent`、`unknowns`，交 S7 evidence-check 校验。 | 整个 synthesis 载荷 |

## 2. 九类场景 method 库（method id 命名 `<scene-slug>-v1`）

每类 = 通用六步 + 侧重维度 + 特化步骤（在 S2/S3 注入）。`analysisMethod` 取对应 method id。

| # | 场景 (runtime-spec §3) | method id | 主侧重维度 | 特化步骤 | 三源关键依赖 |
| --- | --- | --- | --- | --- | --- |
| 1 | 实现与需求文档差异核查 | `diff-doc-vs-impl-v1` | root_cause + timeline | 对比「Jira 描述的预期」vs「代码实际实现」；比对工单 `resolvedDate` 与 commit `date` 先后，**定位先变的是 Jira 还是代码**，给差异时间节点 + 责任工单 | jira(描述)+git(时间)+code(实现) 三源缺一即降级 |
| 2 | 新需求影响范围评估 | `impact-scope-v1` | current_state | 沿 code-analyst 调用链输出**模块依赖图**；用 git 历史找该区域**高频共变文件/历史变更模式**，提示隐性耦合 | code(调用链) 主；git(共变) 辅；jira 可缺 |
| 3 | 缺陷责任定位 | `defect-attribution-v1` | timeline | 定位缺陷代码**最后修改 commit + author + 工单**，给带时间线/负责人的证据链；**区分引入 vs 暴露** | git(blame/最后修改) 主；jira(工单) 辅；code 定位 |
| 4 | 新成员知识加速 | `onboarding-knowledge-v1` | root_cause | 三源重建模块**设计决策历程**：关键 commit 的工单业务原因串成「为什么这样设计」叙事 | 三源均需，缺 jira 则只剩「怎么变」缺「为什么」 |
| 5 | 技术债务定性 | `tech-debt-triage-v1` | root_cause | 区分「有业务原因的历史决策」（工单可溯）vs「未清理的临时方案」（无工单 / TODO / hotfix 无后续），**按是否可溯分类** | jira(有无原因) 是分类关键；git/code 提供痕迹 |
| 6 | 回归缺陷溯源 | `regression-trace-v1` | timeline | 定位该逻辑**最近被触碰的 commit + 工单**，**区分主动修改**（工单明确改此处）vs **隐藏缺陷**（顺带触碰无意图） | git(最近触碰) 主；jira(意图) 判主动/被动；code 定位 |
| 7 | 功能蒸发追踪 | `feature-evaporation-v1` | timeline | 还原功能被**删除/Revert 的 commit + 工单 + 删除前最后修改**；利用 `Revert "DELI-..."`（`isRevert=true`）与删除型 diff（core-ng 定稿 §5） | git(删除/Revert commit) 主；jira(为何删) 辅 |
| 8 | 跨团队接口争议仲裁 | `interface-arbitration-v1` | current_state + timeline | 并排「接口约定变更记录（工单 / `-interface` 模块 commit）」vs「实现侧代码记录」，**把争论转为事实核对**；跨仓常见，注意 `reposInvolved` 两侧都要 | code(两侧实现)+git(两侧变更史) 主；jira 佐证约定 |
| 8.1 | 跨仓因果链追踪 | `cross-repo-causal-v1` | chainSteps | 当 repo_timeline 含 `crossRepoEvidence` 时触发。五步法：①识别仓库 ②分组时间线 ③找交叉点（导出方版本变更 + 消费方版本升级）④建因果方向 ⑤产出 chainSteps | crossRepoEvidence(主)+两侧时间线(主)；matchMethod 标注证据强度 |
| 9 | 设计与实现对齐审查（含 Figma） | `design-impl-alignment-v1` | current_state | **二期 stub（标二期、不实现）**：并排「代码改了什么」vs「设计意图(Figma)」，明确偏差来源；依赖 design-tracer。占位保结构、首版不执行 | + Figma 源（二期） |


## 3. method 选择与降级

- 选型来源：dongmei-ma `query_plan.intent` / `scenario`（契约 §2.1，intent 枚举对齐场景 1~9）。
- intent 未明或跨场景 → 通用六步，`analysisMethod=synthesis-core-generic-v1`。
- 任一场景三源不全时**不空想**：缺的维度进 `unknowns`，由 S7 evidence-check 判置信度并可能触发返工——本骨架不负责补源（补源靠契约 §7 返工循环）。

## 4. evidence 组织规范（每条结论挂出处）

- `conclusion.evidence[]` 用统一出处对象（契约 §2.5）：`{type, ref}`，`type ∈ {code, commit, jira, kb}`，`ref` 为可定位引用。
- synthesizer 产 evidence 不含直接 MCP 调用结果——全部来自对应 agent 的产出（边界约束，契约 §5）。
- `sourcesPresent{code,git,jira}` 按实际挂上的出处类型如实填写。

## 5. unknowns 标注规范

进 `unknowns` 的情形：① 无出处的判断；② 三源冲突未解的另一方；③ 场景关键维度缺源。每条 unknown 文本应可被 verifier 映射到缺环（见 evidence-check SKILL.md §D 缺口格式）。

