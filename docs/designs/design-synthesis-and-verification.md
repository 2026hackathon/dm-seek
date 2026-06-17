# 综合(synthesizer) + 校验(evidence-verifier) 方法论

> synthesizer 的九类场景分析方法骨架 + evidence-verifier 的三级置信度判据、逐结论出处校验规则、缺口标注格式。

---

## 第一部分：synthesizer 分析方法

## 1. 通用分析骨架（沉淀为可复用 skill：`synthesis-core`）

所有 9 类场景共享一套**通用综合骨架**，差异只在「侧重维度」与「特化步骤」。把通用骨架沉淀为单一可复用 skill `synthesis-core`，各场景方法以「骨架 + 场景特化片段」组合，避免重复。

`synthesis-core` 六步（对每次综合恒定执行）：

| 步 | 名称 | 动作 | 产出落点（契约 §2.7 synthesis） |
| --- | --- | --- | --- |
| S1 | 三源对齐 | 把 code_location_set / repo_timeline / jira_reasons 按 **代码实体 ↔ commit ↔ 工单** 三方关联对齐（以代码实体为锚） | `sourcesPresent{code,git,jira}` |
| S2 | 时间线编织 | 按 commit date 排出演变序列，每个节点挂 `工单号 + 业务原因`，标 primary/context | `timelineNarrative` |
| S3 | 结论生成 | 按场景侧重维度生成 `conclusions[]`，每条限定 `dimension∈{current_state,timeline,root_cause}` | `conclusions[].statement/dimension` |
| S4 | 出处挂接 | 每条结论强制挂 `evidence[]`（code/commit/jira），无出处的判断移入 `unknowns` 而非冒充结论 | `conclusions[].evidence` / `unknowns` |
| S5 | 矛盾标记 | 标记三源互相冲突处（如代码现状与工单描述不符——正是「马冬梅」要解的认知偏差）；冲突以**代码为准**陈述，并记录冲突另一方 | 写入对应 conclusion + unknowns |
| S6 | 自检交棒 | 填 `analysisMethod` 标识、`sourcesPresent`、`unknowns`，交 evidence-verifier | 整个 synthesis 载荷 |

> **以代码为锚**是 S1/S5 的硬约束：当 Jira 描述/记忆与代码现状冲突，结论按代码事实陈述，把冲突的另一方记为「记录与实现的偏差」，不和稀泥。

## 2. 九类场景方法骨架

每类 = `synthesis-core` + 侧重维度 + 特化步骤。`analysisMethod` 取值即各场景 method id（命名规范 `<scene-slug>-v1`）。

| # | 场景 | method id | 主侧重维度 | 特化步骤（在 S2/S3 注入） | 三源关键依赖 |
| --- | --- | --- | --- | --- | --- |
| 1 | 实现与需求文档差异核查 | `diff-doc-vs-impl-v1` | root_cause + timeline | 对比「Jira 描述的预期」vs「代码实际实现」，定位**先变的是 Jira 还是代码**（比对工单 resolvedDate 与 commit date 先后），给差异时间节点 + 责任工单 | jira(描述) + git(时间) + code(实现) 三源缺一即降级 |
| 2 | 新需求影响范围评估 | `impact-scope-v1` | current_state | 沿 code-analyst 调用链输出**模块依赖图**；用 git 历史找该区域**历史变更模式/高频共变文件**，提示隐性耦合 | code(调用链) 主；git(共变) 辅；jira 可缺 |
| 3 | 缺陷责任定位 | `defect-attribution-v1` | timeline | 定位缺陷代码**最后修改 commit + author + 工单**，给带时间线/负责人的证据链；区分引入 vs 暴露 | git(blame/最后修改) 主；jira(工单) 辅；code 定位 |
| 4 | 新成员知识加速 | `onboarding-knowledge-v1` | root_cause | 三源重建模块**设计决策历程**：关键 commit 的工单业务原因串成「为什么这样设计」叙事 | 三源均需，缺 jira 则只剩「怎么变」缺「为什么」 |
| 5 | 技术债务定性 | `tech-debt-triage-v1` | root_cause | 区分「有业务原因的历史决策」（工单可溯）vs「未清理的临时方案」（无工单/标注 TODO/hotfix 无后续）；按是否可溯分类 | jira(有无原因) 是分类关键；git/code 提供痕迹 |
| 6 | 回归缺陷溯源 | `regression-trace-v1` | timeline | 定位该逻辑**最近被触碰的 commit + 工单**，区分**主动修改**（工单明确改此处）vs **隐藏缺陷**（顺带触碰无意图） | git(最近触碰) 主；jira(意图) 判主动/被动；code 定位 |
| 7 | 功能蒸发追踪 | `feature-evaporation-v1` | timeline | 还原功能被**删除/Revert 的 commit + 工单 + 删除前最后修改**；利用 `Revert "DELI-..."` 与删除型 diff（见 core-ng 定稿 §5） | git(删除/Revert commit) 主；jira(为何删) 辅 |
| 8 | 跨团队接口争议仲裁 | `interface-arbitration-v1` | current_state + timeline | 并排「接口约定变更记录（工单/interface 模块 commit）」vs「实现侧代码记录」，把争论转为事实核对；跨仓常见 | code(两侧实现) + git(两侧变更史) 主；jira 佐证约定 |
| 9 | 设计与实现对齐审查（含 Figma） | `design-impl-alignment-v1` | current_state | **二期**：并排「代码改了什么」vs「设计意图（Figma）」，明确偏差来源；依赖 design-tracer | + Figma 源（二期）；首版不实现 |

> 沉淀决策：**`synthesis-core` 是唯一强制 skill**；9 个场景方法以「method 片段」形式收在同一 skill 的场景库内（单 skill 多 method，类比 core-ng 规则集中一处），不为每场景建独立 skill，避免碎片化。场景 9 标记二期、占位不实现。

## 3. 场景选择与降级

- synthesizer 据 dongmei-ma `query_plan.intent`/`scenario`（契约 §2.1）选 method；intent 未明或跨场景 → 用 `synthesis-core` 通用六步，`analysisMethod` 记 `synthesis-core-generic-v1`。
- 任一场景在三源不全时**不空想**：缺的维度进 `unknowns`，由 verifier 判置信度并可能触发返工——方法骨架不负责补源，补源靠返工循环（契约 §7）。

---

## 第二部分：evidence-verifier 校验

## 4. 逐结论出处校验规则

对 `synthesis.conclusions[]` 每条执行：

1. **出处存在性**：`evidence[]` 非空 → `hasEvidence=true`；空 → `false`，该结论 `ok=false`，必入 gaps。
2. **出处类型记录**：`evidenceTypes` = evidence 中出现的 `type` 去重（code/commit/jira/kb）。
3. **出处可回挂性（抽检）**：ref 格式合法（路径#行 / repo@sha / 工单号 / KB 路径#行，契约 §2.5）；格式非法视同无效出处。
4. **维度-出处匹配**：
   - `root_cause` 维度的结论**应**有 `jira`（或明确的 commit message 业务说明）出处；只有 code/commit 支撑的「原因」判断 → 标为推断，降级。
   - `current_state` 维度**应**有 `code` 出处。
   - `timeline` 维度**应**有 `commit` 出处。
   - 维度缺对应出处类型 → 该结论 `ok=false` 或降级标记。
5. **结论 ok 汇总**：所有关键结论 ok 且无遗漏维度 → 倾向 sufficient。

## 5. 三级置信度判据

主判据（基于 `sourcesPresent` + 逐结论校验）：

| 置信度 | 判据（全部满足） |
| --- | --- |
| **高** | code ∧ git ∧ jira 三源齐备；**且互相印证**（S5 无未解冲突）；**且**每条结论均挂合法出处、维度-出处匹配。**root_cause 维度须有独立 jira 工单印证** |
| **中** | 三源不全但核心成立：缺 jira 业务原因（有 code+git，知「怎么变」不知「为什么」）；**或**仅有 git 时间线缺 code 解读印证；**或** root_cause 仅由含充分业务说明的 commit message 顶替独立 jira 工单（**此情形置信度封顶为中**）；结论仍各有出处 | 
| **低** | 关键结论主要依赖推断、缺直接出处；**或**仅单源；**或**三源互相矛盾且无法以代码为锚定论 |

附加下调因素（命中则在主判据基础上**下调一档**或显式标注，来自双源/路由与抽取风险）：

| 因素 | 来源 | 处置 |
| --- | --- | --- |
| `repo_timeline.shallowWarning=true` | 本地 shallow，历史不全 | 时间线可疑，下调或标注 |
| `reposCovered ⊊ reposInvolved`（漏仓） | 多仓未覆盖（路由定稿 §4.3） | 计 gaps，触发 add_repos |
| `jira_reasons.missingTickets` 非空 | 有号查不到工单 | root_cause 削弱，下调 |
| 大量 `noTicket` commit | 时间线无法挂原因 | 中→低风险 |
| 态 C 用本地 / 无法比对远端（路由定稿 §5） | 代码现状可能非最新 | 标注，不必然降级 |

> 「互相印证」操作化：S1 对齐的 代码实体↔commit↔工单 三元能闭环（改了 X 的 commit 挂着工单 Y、Y 的业务原因解释了 X 的现状），且 S5 无未解冲突，才算印证 → 高。

## 6. 缺口标注格式（契约 §2.8 gaps，与发散清单对齐）

每个缺口结构化为：

```json
{
  "missingSource": "jira",
  "whichConclusion": "变更原因为缩短库存占用",
  "missingLink": "root_cause_reason",
  "detail": "commit DELI-4521 抽到工单号，但 Jira 未返回业务原因（missingTickets）",
  "suggestedHint": "retry_missing_tickets"
}
```

| 字段 | 说明 |
| --- | --- |
| `missingSource` | 缺哪一源：`code`/`git`/`jira` |
| `whichConclusion` | 关联到哪条结论（缺口必须可定位到具体断言） |
| `missingLink` | 缺哪一环（语义化）：`kb_clue`(线索) / `code_location`(定位) / `code_interpretation`(解读) / `git_timeline`(时间线) / `ticket_extraction`(抽号) / `jira_reason`(业务原因) / `repo_coverage`(仓库覆盖) |
| `detail` | 给用户/降级报告直接呈现的具体缺口说明 |
| `suggestedHint` | 建议的发散动作（取值自契约 §7.3 的 9 项枚举），填入 `verification.divergeHints` |

**缺环 → 发散 hint 映射**（verifier 据此填 divergeHints，dongmei-ma 据此重派，契约 §7.3）：

| missingLink | 默认 suggestedHint |
| --- | --- |
| `kb_clue` | `widen_kb_search` / `kb_to_source_fallback` |
| `code_location` / `code_interpretation` | `expand_code_scope` |
| `repo_coverage` | `add_repos` |
| `git_timeline` | `extend_git_history` |
| `ticket_extraction` | `relax_ticket_regex` |
| `jira_reason`（有号缺因） | `chase_linked_tickets` / `retry_missing_tickets` |
| 结论与证据不匹配/推断过多 | `reframe_synthesis` |

## 7. verdict 与返工决策（verifier 输出 → dongmei-ma 驱动）

- `verdict=sufficient`：confidence∈{高,中}（中亦可交付，但报告显式标置信度与已知缺口）→ dongmei-ma 交付 + 沉淀。
- `verdict=insufficient`：通常 confidence=低或关键结论 ok=false → dongmei-ma 据 round 决定发散（<2）或降级交付（==2，契约 §7.1）。
- verifier **只判定与建议**，不自行重派（重派是 dongmei-ma 职责，契约 §7）；verifier 跨轮对比 gaps 是否收敛，未收敛则在 divergeHints 提示「换策略」（契约 §7.3 防空转）。

> 中置信度可交付但显式标注：返工只为把「低/不足」救到「中/高」，不为把「中」刷到「高」而空转。

---

## 8. 对下游

- **synthesizer**：实现 `synthesis-core` 六步为单一 skill；9 场景 method 收于同一 skill 场景库（单 skill 多 method）；以代码为锚、缺源入 unknowns 不空想。
- **evidence-verifier**：实现 §4 逐结论校验 + §5 三级判据（含附加下调因素）+ §6 缺口格式与 hint 映射；只判定不重派。
- **分析方法 skill**：即 `synthesis-core` skill（含 9 场景 method 场景库），落项目级 `.claude/skills/synthesis-core/`。
