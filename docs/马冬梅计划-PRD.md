# 马冬梅计划 — 产品需求文档（PRD）

| 项目 | 内容 |
| --- | --- |
| 产品名 | 马冬梅计划（dm-seek） |
| 定位 | 面向研发全角色的「代码现实 × 需求演进」追溯系统 |
| 形态 | 可导入、开箱即用的 **Claude Code 成品 agent team**（7 个平级 teammate + 共享配置；非自建框架、非 subagent 父子委派） |
| 引擎 | Claude Code，直连 Anthropic API（仅 Claude） |
| 运行环境 | 本地 CLI 进程，跨 Windows / macOS |
| 文档版本 | v0.4.3（承 v0.4.2 优化A/B；本版新增：**1** 全局只读政策（代码/Git/GitHub/Jira 全部只读，仅 `git fetch` + KB 写例外，§6.5）；**2** synthesizer 双层输出（`executiveSummary` + 完整结论，§4.1 step7 / §4.3）；**3** code-analyst/repo-tracer prompt 精简（附录A） |
| 日期 | 2026-06-13 |
| 负责人 | architect |
| 状态 | v0.4.2 已通过；本版（v0.4.3）融入只读政策 + synthesizer 双层输出 + agent prompt 精简，待用户确认 |

> 来源参考：`D:\wechat_files\xwechat_files\wxid_4lzbvrnoaov212_26e7\msg\file\2026-06\马冬梅计划.html`（背景与场景参考）。本 PRD 以 tech-lead 转交的「需求基线」为权威依据；凡基线与来源 HTML 不一致处，一律以基线为准（基线相对 HTML 的主要演进见附录 A）。

---

## 1. 项目背景与定位

### 1.1 问题：四个孤岛与认知偏差

一个功能的完整认知，天然分散在四个互相割裂的信息孤岛中：

- **代码库** —— 它现在「是什么样」（现状 / 事实）
- **Git 历史** —— 它「怎么一步步变成今天这样」（演变过程）
- **Jira** —— 每次变更「为什么发生」（业务原因）
- **Figma**（可选） —— 当初的「设计意图与视觉演变」

当任何一方与「某人的记忆」产生认知偏差时，就会引发**沟通摩擦、决策失误、责任争议**。现实中没有一个统一入口能把四源串起来回答「这个功能现在是什么样、怎么变成这样、为什么变」。

### 1.2 定位：以代码为唯一事实基准的叙事链

马冬梅计划把分散的四源串联成**一条有证据的叙事链**，核心原则是 **以代码为唯一事实基准（code as the single source of truth）**：

- 一切结论必须能回挂到具体的**代码 / commit / Jira 工单**出处；
- 当「代码现实」与「某人的记忆 / 文档描述」冲突时，以代码为锚点给出带时间线的事实，而非一场没有结论的回忆录。

### 1.3 产品形态

马冬梅计划是一套 **Claude Code 成品 agent team**：以 Claude Code 为运行引擎，交付一份可导入、开箱即用的团队配置（角色定义 `.claude/agents/`、共享 skills、共享 MCP 配置占位、文档与测试）。

- **运行形态 = agent team teammate**（用户裁决，路径 B）：7 个 agent 是**平级 teammate**，经**共享任务列表 + 消息**协作，而**非** subagent 父子委派（即非「一个主 agent 用 Task 工具逐个调用子 agent 并独占返回」的模型）。`dongmei-ma` 是 team 内的**协调者 teammate**（角色定位类似本开发队的 tech-lead：拆解任务、驱动校验返工循环、对用户交付），但它**不是**其他 agent 的「父」，不通过委派独占下游。
- 它**不是**一个自建的 agent 框架，也不引入 Claude 以外的 LLM。
- 该形态下，**MCP 与 skills 从项目级共享配置加载**（共享 `.mcp.json`、项目级 `.claude/skills/`），而非写在各 agent frontmatter 的 `mcpServers` / `skills` 字段——后者在 teammate 形态下**不生效**（详见附录 B）。因此「独占」是**边界约束（双层边界 / 三道防线）**而非物理隔离（详见 §6.2、§6.4、§11.1）。

---

## 2. 目标与成功标准

### 2.1 目标

让研发团队的任意角色，用**一句自然语言疑问**，得到一份**有证据、带置信度**的功能演变报告：当前实现状态 + 演变时间线 + 根因解释。

### 2.2 成功标准

1. 用户输入一句自然语言疑问，team 能自动完成「KB 线索 → 代码定位与解读 → Git 时间线 + 工单号抽取 → Jira 业务原因 → 综合结论 → 证据校验」全流程，输出含**置信度**的报告。
2. 每条结论都挂有**代码 / commit / 工单**出处；证据不足时能**自动触发发散返工**，扩大搜索后重新综合，而非给出无依据的答案。
3. 在**无本地知识库**时，能通过 KB 初始化能力，基于代码仓库 + Jira **自建粗粒度知识库**；后续查询过程中细粒度沉淀，实现知识自增长。
4. 在**无本地仓库**时（典型为非研发用户），能全程经 GitHub MCP 获取代码与提交历史完成溯源。
5. 交付物为**可导入的 Claude Code 团队配置包**，在 Windows 与 macOS 上经一步引导式配置即可开箱即用。
6. 首版能正确识别并解读 **core-ng** 框架代码（REST 入口、Kafka 入口、调用链），识别**基于代码中的实际标志**而非框架惯例猜测。

---

## 3. 用户与使用形态

### 3.1 目标用户

面向**研发 + 非研发全角色**：

- 研发：开发、测试、架构（通常有本地仓库）
- 非研发：PM、设计相关角色（通常无本地仓库，经 GitHub MCP 取代码）

### 3.2 使用形态

- 本地 **CLI 进程**（Claude Code），跨 Windows / macOS。
- 用户以自然语言提问；team 内部 7 个平级 teammate 经**共享任务列表 + 消息**协作完成溯源；最终由协调者 `dongmei-ma` 交付报告。
- 凭据（Jira / GitHub / Figma 的 URL / 邮箱 / Token 等）由用户自填，引导 skill 协助完成配置。

---

## 4. 核心查询溯源流程（含校验返工循环）

### 4.1 流程步骤

1. 用户提出一句自然语言疑问。
2. **dongmei-ma**（协调者 teammate）解析疑问，拆解为子任务、派发到共享任务列表并以消息驱动协作（非父子委派）。
3. **kb-keeper** 查询知识库（KB），给出线索（模块、路径、核心类等候选）。
4. **code-analyst** 据 KB 线索**定位具体代码并解读**（core-ng）。
   - 本地有仓库且相关代码段不过时（态B）：直接读本地文件；并可**直接读本地 git 历史**（经 Bash 读本地 git log）作本地 git 证据片段，附给 repo-tracer 收口（优化A，见 §7.4）；
   - 无本地仓库（远端模式）：经 **repo-tracer** 取代码内容与远端提交历史；
   - KB 未命中：回源码兜底（直接在代码中搜索定位）。
   - **审视 KB 匹配性**（优化B）：拿到 KB 线索后**先读实际代码**，比对「KB 描述 vs 代码现实」（KB 可能粗粒度或过时），**以代码为锚**给出匹配度结论（consistent / partial / stale / contradicted / kb_miss）与逐条偏差——帮助后续环节理解 KB 可信度；KB 偏差按「以代码为准」处理，**不冒充结论缺证据**（见 §6.1、§7.2）。
5. **repo-tracer** 统一收口产出**提交时间线**，并从 commit subject 中**抽取 Jira 工单号**。态B 本地非过时仓：**信任并采用 code-analyst 附来的本地 git 片段**（不重复跑 git log），未附则自取兜底；远端经 GitHub MCP（独占）。无论来源，时间线收口与抽工单号均归 repo-tracer（优化A）。
6. **jira-tracer** 经 **Jira MCP** 取对应工单的**业务原因**与因果脉络。
7. **synthesizer** 综合 code + git + jira 三源，产出**双层结论**：① **`executiveSummary`**（面向非技术人员的自然语言结论摘要，用纯业务语言将 Jira 业务原因与代码高层影响编织为连贯叙事，以一段简述收官；默认不暴露类名/方法名等代码标识，代码与 Jira 有出入时例外允许暴露以定位差异）；② **完整结论**（按场景的结构化分析，含证据链、偏差注记、场景特定评估）。三源/KB 与代码冲突时以代码为准、记为「记录与实现的偏差」。
8. **evidence-verifier** 校验证据充分性并给出**置信度（离散三级：高 / 中 / 低）**：
   - 判据：三源（code + git + jira）齐备且互相印证 = **高**；缺 Jira 业务原因、或仅有 git 时间线 = **中**；结论主要依赖推断、缺直接出处 = **低**。
   - **KB 偏差不下调置信度**（优化B 红线）：code-analyst 报的 KB 匹配偏差（stale / contradicted / partial）仅作 KB 可信度注记，**不触发证据不足、不下调置信度、不触发返工**——KB 偏差只说明 KB 旧了、本次靠源码坐实，与结论三源充分性无关。
   - **充分** → dongmei-ma 交付报告；kb-keeper 把结论**沉淀回 KB（`queries/`）**。
   - **不足** → dongmei-ma **发散重派**、扩大搜索范围后重新综合（回到第 4~7 步），形成**校验返工循环**。
   - **返工上限：最多 2 轮发散返工**。两轮后仍不足时，**降级交付**：照常出报告，但**明确声明「证据不足」并标注具体缺口**（缺哪一源/哪一环），不无限循环、不臆造结论。

> **多 agent 增量沉淀（优化B，知识增量积累）**：除终局由 dongmei-ma 委托 kb-keeper 沉淀**最终结论**（写 `queries/` 权威区）外，code-analyst / repo-tracer / jira-tracer 在本次调查中各自把值得沉淀的**增量发现**（KB 偏差校正、KB 未覆盖的入口/调用链、新 commit/工单线索、业务原因因果链等）随产物上报；dongmei-ma **终局统一归并**后交 kb-keeper，由其 `append` 写入 `modules/` / `entrypoints/` 细粒度增量区（与 `queries/` 权威结论区分）。三个调查 agent **绝不自写 KB**（KB 写仍唯一收口 kb-keeper），且**终局归并而非边跑边写**——保 KB 写独占 + 防并发竞态 + 只沉淀经全链路校验的内容。

### 4.2 流程图

```
            用户一句自然语言疑问
                     │
                     ▼
            ┌──────────────────┐
            │   dongmei-ma     │  协调者: 解析疑问 / 拆解任务
            │   (协调者teammate)│  / 派发任务列表 / 消息驱动
            └──────────────────┘
                     │
                     ▼
            ┌──────────────────┐
            │    kb-keeper     │  查 KB → 给线索
            └──────────────────┘
                     │  线索
                     ▼
            ┌──────────────────┐   远端模式取代码内容
            │   code-analyst   │◄──────────────┐
            │ 定位+解读(core-ng)│               │
            │ KB未命中→源码兜底 │               │
            └──────────────────┘               │
                     │                          │
                     ▼                          │
            ┌──────────────────┐                │
            │   repo-tracer    │  Git/GitHub 网关
            │ 时间线+抽工单号   │  (边界独占 GitHub MCP)
            └──────────────────┘
                     │  工单号
                     ▼
            ┌──────────────────┐
            │   jira-tracer    │  Jira MCP → 业务原因
            └──────────────────┘
                     │
                     ▼
            ┌──────────────────┐
            │   synthesizer    │  综合 code+git+jira → 结论
            └──────────────────┘
                     │
                     ▼
            ┌──────────────────┐
            │ evidence-verifier│  校验出处 + 置信度
            └──────────────────┘
              充分 │      │ 不足
        ┌──────────┘      └──────────┐
        ▼                            ▼
  dongmei-ma 交付          dongmei-ma 发散重派
  kb-keeper 沉淀回KB        扩大搜索 ↺ 回到 code-analyst
   (queries/)               (最多 2 轮; 仍不足→降级交付,
                             声明「证据不足」并标注缺口)
```

### 4.3 输出

- **`executiveSummary`**（非技术人员可读的结论摘要：纯业务语言叙事，Jira 业务原因与代码高层影响编织为连贯叙事，以一段简述收官；默认不暴露代码标识，代码与 Jira 有出入时例外）
- **当前实现状态**（代码现实）
- **演变时间线**（Git，含关联工单号）
- **根因解释**（Jira 业务原因）
- **置信度**（evidence-verifier 评估，高 / 中 / 低；证据不足时显式声明并标注缺口）
- **语言：默认产出中文报告**——dongmei-ma 默认以**中文**交付报告（含 `executiveSummary` 中文）；系统仍支持中英双语，**英文版按需/附随提供**（非默认每次产出，由用户请求或在需要时生成）。
- **副产品**：结论自动沉淀至 KB `queries/`，同类问题下次秒答。

---

## 5. 应用场景

> 以下为首批已识别的应用场景。**该清单可扩展，后续可能继续添加新场景**——不视为封闭集合。

| # | 场景 | 主要角色 | 价值 |
| --- | --- | --- | --- |
| 1 | 实现与需求文档差异核查 | PM | 定位「Jira 先变还是代码先变」，给出差异时间节点与责任工单 |
| 2 | 新需求影响范围评估 | PM / 开发 | 输出模块依赖与历史变更模式，提前识别隐性耦合 |
| 3 | 缺陷责任定位 | 测试 | 追溯最后修改 commit 与工单，给出带时间线/负责人的证据链 |
| 4 | 新成员知识加速 | 开发 | 三源重建模块设计决策历程，隐性知识显式化 |
| 5 | 技术债务定性 | 开发 | 区分「有业务原因的历史决策」与「未清理的临时方案」 |
| 6 | 回归缺陷溯源 | 开发 / 测试 | 定位逻辑最近被触碰的 commit 与工单，区分主动修改 vs 隐藏缺陷 |
| 7 | 功能蒸发追踪 | PM / 测试 | 还原功能被删除的 commit、工单与删除前最后修改 |
| 8 | 跨团队接口争议仲裁 | 前端 / 后端 / 测试 | 并排「约定变更记录 vs 代码实现记录」，争论转事实核对 |
| 9 | 设计与实现对齐审查（含 Figma） | PM / 测试 | 并排「代码改了什么」与「设计意图」，明确偏差来源（二期能力） |

> 说明：场景 9 依赖 Figma 追溯，属二期能力（见第 6、10 节）。

---

## 6. 团队角色设计（7 + 1）

> 全部使用**纯英文 id，无中文名**。首版 7 个 agent；`design-tracer` 为二期。
>
> **运行形态**：7 个 agent 是**平级 teammate**（非 subagent 父子委派），经共享任务列表 + 消息协作。下表「职责域 / 允许 MCP（L1 白名单）」描述的是**双层边界**约束（详见 §6.2 的三道防线），**非物理隔离**：L1 屏蔽机制已获真实 CLI 正面佐证、live 端到端演示待部署环境，边界由 L1 白名单 + 每 agent 显式边界声明 + evidence-verifier 校验共同保证。每个 agent 定义须含固定区块「## 职责范围 / ## 允许使用的 MCP 服务 / ## 边界约束」。

### 6.1 角色清单

> 「允许 MCP（L1 白名单）」列给出各 agent `tools` 白名单中**允许的源类 `mcp__` 工具**；未列即**禁止**（边界约束硬性禁调领域外 MCP，跨域经任务列表/消息向 owner agent 请求）。

| # | id | 职责 | 职责域 / 允许 MCP（L1 白名单） | 阶段 |
| --- | --- | --- | --- | --- |
| 1 | `dongmei-ma` | **协调者 teammate**（角色定位类似本开发队 tech-lead）：用户接口、解析疑问、拆解任务并派发到共享任务列表、以消息驱动校验返工循环、最终交付（**默认产出中文报告**，英文版按需/附随提供）；委托 kb-keeper 沉淀最终结论 + **终局归并各 agent 增量发现一并交 kb-keeper**（优化B，自身不写 KB）；非其他 agent 的父、不通过 Task 委派独占下游 | 域=协调/用户接口。允许 MCP：**无**（白名单不含任何源类 `mcp__` 工具，不直连信息源） | 首版 |
| 2 | `kb-keeper` | **边界唯一 Obsidian 读写口**：从 KB 给线索 + 结论沉淀回写；**不读源码**。集成方式：obsidian CLI（search / read / create / append）+ Knowlery 技能 `/ask`（检索线索、带引用）+ `/cook`（按 SCHEMA 编译结论沉淀至 `queries/`）；区分**权威结论**（`/cook` 写 `queries/`）与**多 agent 增量发现**（`append` 写 `modules/` / `entrypoints/`，与权威结论隔离，优化B） | 域=知识库读写。允许：KB/obsidian 工具（obsidian CLI / Knowlery 技能，**非 `mcp__`**）。禁止：源码、GitHub/Jira MCP | 首版 |
| 3 | `code-analyst` | 据 KB 线索**定位具体代码 + 解读代码**（core-ng）；**审视 KB 与实际代码的匹配性**（优化B，以代码为锚给匹配度+偏差）；KB 未命中回源码兜底；KB 初始化时遍历入口点/调用链的执行者；将定位结果**映射到具体 repo + 模块**，告知 repo-tracer 涉及哪些仓库；**态B 本地非过时仓可经 Bash 直读本地 git 历史**作本地 git 证据片段附给 repo-tracer（优化A，远端历史仍经 repo-tracer） | 域=代码定位与解读。允许：本地代码读取工具（Read/Grep/Glob）+ 本地 git（Bash，**与 repo-tracer 共享、非独占**）。禁止：GitHub MCP（远端代码/远端历史经 repo-tracer 取）、Jira MCP、KB 写 | 首版 |
| 4 | `repo-tracer` | Git / GitHub 仓库网关，**边界独占全部 GitHub MCP 实例（远端取码 + 远端提交历史）**；**统一收口产出提交时间线**——态B 本地非过时仓**信任并采用 code-analyst 附来的本地 git 片段**（不重复跑 git log），未附则经 Bash 自取兜底（本地 git 读取权与 code-analyst 共享、非独占，优化A）；远端经 GitHub MCP；**管理 N 个按仓库划分的 GitHub MCP 实例（一个 MCP 服务 ↔ 一个 git repo，各自独立 token），支持一次查询横跨多仓**；**始终从 commit subject 抽取 Jira 工单号**（默认正则 `[A-Z]+-\d+`，本仓 `DELI-\d+`，可配置，容错无号提交） | 域=Git/GitHub 网关。允许：`mcp__github-*`（全部 GitHub MCP 实例工具，**远端独占**）+ 本地 git（Bash，**与 code-analyst 共享**）。禁止：Jira MCP、KB 写 | 首版 |
| 5 | `jira-tracer` | 经 **Jira MCP** 取工单业务原因与多工单因果脉络 | 域=Jira 业务原因。允许：`mcp__jira__jira_get`（**只读**）。禁止：Jira 写工具、GitHub MCP、KB 写 | 首版 |
| 6 | `synthesizer` | 综合 code + git + jira → 结论（对应 9 类场景：质量评估 / 影响范围 / 变更脉络等）；三源/KB 与代码冲突以代码为准、记为「记录与实现的偏差」；**分析方法沉淀为可复用 skill** | 域=综合分析（仅消费上游三源产物）。允许 MCP：**无**（不直连任何源） | 首版 |
| 7 | `evidence-verifier`（critic 角色） | 校验每条结论是否挂着 **代码 / commit / 工单**出处 + 输出**置信度** + 不足时**触发发散返工**；**校验层**：标记「结论引用声明范围外工具 / 数据来源」的边界违规（运行期兜底；本地 git=code-analyst/repo-tracer 共享合法，远端 GitHub MCP 仅 repo-tracer 合法，优化A）；**KB 偏差仅作可信度注记、不下调置信度**（优化B 红线） | 域=证据/边界校验（仅消费上游全部产物）。允许 MCP：**无**（不直连任何源） | 首版 |
| 8 | `design-tracer` | Figma 设计追溯：设计上下文与视觉演变 | 域=设计追溯。允许：Figma MCP（二期） | **二期** |

### 6.2 关键归属约束（独占 = 双层边界 / 三道防线）

> **用户最终裁决（维持路径 B）**：共用 `.mcp.json` 可接受；但**每个 agent 必须显式声明「职责范围 + 允许使用的 MCP 服务」，明确禁止调用领域外 MCP 服务，边界清晰**。据此，本系统的「独占」最终定义为**三道防线**叠加，而非单一机制。

**三道防线**

1. **L1 技术层（tools 白名单）**：各 agent frontmatter 的 `tools` 白名单**只含本域工具**——`repo-tracer` 仅 `mcp__github-*`；`jira-tracer` 仅 `mcp__jira__jira_get`（只读）；`kb-keeper` 仅 KB/obsidian 工具（经 obsidian CLI / Knowlery 技能，**非 `mcp__` 工具**，故不含任何源类 `mcp__`）；`dongmei-ma` 不含任何源类 `mcp__`；`code-analyst` 仅本地代码读取工具；`synthesizer` / `evidence-verifier` 不含任何源类 `mcp__`（仅消费上游产物）。
2. **声明层（agent 定义固定区块）**：每个 agent 定义含三段固定区块——
   - `## 职责范围`：本 agent 的域与产出；
   - `## 允许使用的 MCP 服务`：枚举本域允许的 `mcp__` 服务/工具（与 L1 白名单一致）；
   - `## 边界约束`（硬性）：**禁止调用领域外 `mcp__` 工具**；跨域需求**经任务列表 / 消息向 owner agent 请求**（如 code-analyst 远端取码 → 请求 repo-tracer），**绝不直接调领域外 MCP**。
3. **校验层（evidence-verifier 运行期兜底）**：`evidence-verifier` 校验结论时，**标记「结论引用了声明范围外的工具 / 数据来源」的边界违规**，作为运行期兜底；与置信度校验同处一环。

**逐项归属（在三道防线下成立）**

- **远端 GitHub MCP 独占于 `repo-tracer`**：仅其 L1 白名单含 `mcp__github-*`；其余 agent 声明层明确禁调。多仓场景下每 git repo 一个独立 GitHub MCP 实例（独立 token），均由 repo-tracer 管理与路由。**独占口径收窄（优化A）**：独占仅针对**远端 GitHub MCP**（取码 + 远端提交历史）；**本地 git 历史读取权 `code-analyst` 与 `repo-tracer` 共享、非独占**——本地 git 经 Bash 直读、无远端凭据风险，态B 本地非过时仓由 code-analyst 直读本地 git 片段附给 repo-tracer 收口（未附则 repo-tracer 自取）。
- **远端模式**下，`code-analyst` 需要的代码内容**与远端提交历史均经 `repo-tracer` 取得**（自身无 GitHub MCP 工具、声明层禁调），以任务/消息请求实现。
- **跨仓查询**：由 `kb-keeper` 线索 + `code-analyst` 定位**映射到具体 repo + 模块**，再由 `repo-tracer` 路由到对应 GitHub MCP 实例 / 本地仓库。
- **Obsidian 知识库读写唯一收口于 `kb-keeper`**：仅其 L1 白名单含 KB/obsidian 工具，其余 agent 声明层明确禁调。**多 agent 增量发现（优化B）不破此独占**——code-analyst / repo-tracer / jira-tracer 只把增量发现作为产物字段上报（非 KB 写动作，L1 白名单不含任何 KB 写路径），由 dongmei-ma 终局归并交 kb-keeper 落库，写库仍唯一收口于 kb-keeper。
- `dongmei-ma` 协调与用户接口层，L1 白名单**不含任何源类 `mcp__` 工具**，声明层亦明确不直连任何信息源；归并增量发现转交 kb-keeper 时**自身不写 KB**。

> **诚实声明（口径，必须随交付文档发布）**：本系统的「独占」= **L1 tools 白名单 + 每 agent 显式边界声明 + evidence-verifier 校验** 三者叠加。**L1 白名单对 `mcp__` 工具的屏蔽机制已由真实 CLI 正面佐证**——实测以 `--agent` 启动的会话，其可用工具集 = 该 agent 声明的精确白名单（非默认全量），`mcp__` 工具受该白名单管辖（须显式声明方得调用）；故未声明 `mcp__` 的 agent 运行时无任何 `mcp__` 工具，L1 屏蔽成立。**live 端到端演示（无权 teammate 试调 live MCP 被挡）待部署环境**（测试项 TC-7.6）——机制已佐证 ≠ live 已坐实。**不得宣称「物理隔离 / 已完成 live 坐实 / 已生效」**。即便 live 演示最终意外不成立，**声明层 + 校验层仍保证边界清晰、可审计**——这正是采用三道防线（而非单押 L1）的理由。

### 6.3 角色协作流程图

见 4.2 流程图。校验返工循环由协调者 `dongmei-ma` 依据 `evidence-verifier` 的判定，经共享任务列表 + 消息驱动（非父子委派）。

### 6.4 运行形态：agent team teammate（用户裁决，路径 B）

**定性**：交付物是一支真正的 **agent team**——7 个**平级 teammate** + 一套共享配置。协作经**共享任务列表 + 消息**完成，**不是** subagent 父子委派（不是「主 agent 用 Task 工具逐个 spawn 子 agent 并独占其返回」的模型）。

- **协调者而非父**：`dongmei-ma` 是 team 内的协调者 teammate（角色定位类似本开发队的 `tech-lead`）：拆解任务、派发到共享任务列表、以消息驱动校验返工循环、对用户交付。它**不**拥有其他 agent，**不**通过委派独占下游产物；下游 teammate 的产物经任务列表/消息对全队可见。
- **MCP / skills 从共享配置加载**：teammate 形态下，MCP 与 skills 由**项目级共享配置**提供——共享 `.mcp.json`（所有 MCP 实例：Jira、N 个 GitHub、二期 Figma）与项目级 `.claude/skills/`（KB 初始化、引导/配置、synthesizer 分析方法等）。**各 agent frontmatter 的 `mcpServers` / `skills` 字段在 teammate 形态下不生效**——已由官方文档双向核实（见附录 B）。
- **独占=三道防线，不止白名单**：MCP 实例对全队共享加载，故 L1 `tools` 白名单是落实归属约束的**技术层**机制；per-agent MCP 独占在当前 Claude Code **仅 L1（tools 白名单）一个原生机制**，其屏蔽机制**已由真实 CLI 正面佐证**（live 端到端演示待部署环境，见 §6.2、附录 B），仍**补强声明层 + 校验层**作纵深防御，使边界不单押在 L1 上。三道防线的完整定义见 §6.2。
- **影响实现（T8 骨架）**：7 个 agent 定义放在 `.claude/agents/`，每个 ① 用 `tools` 白名单收口工具可见性（L1），② 含 `## 职责范围 / ## 允许使用的 MCP 服务 / ## 边界约束` 三段固定区块（声明层）；MCP 配置占位统一进共享 `.mcp.json`；skills 统一进项目级 `.claude/skills/`；**不依赖** frontmatter 的 `mcpServers`/`skills`。`evidence-verifier` 实现含边界违规标记（校验层）。

### 6.5 全局只读政策

**所有对代码、GitHub 仓库、Jira 的操作都是只读的。** 除以下两项外，禁止任何写操作：

1. **`git fetch`**：拉取远端更新本地仓库（唯一允许的 git 写操作），用于过时判定（§7.4 态C）。调用时通过 `--no-auto-gc`/`--no-tags` 等参数最小化副作用。
2. **KB 写操作**：归 kb-keeper，不受此限（KB 自身定位就是知识沉淀存储）。

具体约束：
- **代码文件**：所有 agent 对代码文件只读（Read/Grep/Glob），不修改、不创建、不删除任何代码文件。
- **Git 仓库**：仅允许只读操作（`log`/`diff`/`show`/`cat-file`/`fetch`/`ls-remote`），**严禁** `push`/`commit`/`reset`/`checkout`/`tag`/`rebase`/`stash`/`rm` 等任何改变仓库状态的操作。
- **Jira**：仅允许 `mcp__jira__jira_get`（只读），杜绝任何写/修改工单的操作。
- **GitHub MCP（远端）**：远端 GitHub MCP 调用仅用于取码 + 取提交历史（只读），禁止通过 MCP 创建/修改 PR、issue、comment 等。

> 此政策已在各 agent 边界约束中逐条落地（code-analyst: 代码只读 + git 只读操作；repo-tracer: git 只读清单 + GitHub MCP 只读；jira-tracer: `jira_get` 只读），runtime-spec §4.4 为权威载体。

---

## 7. 能力模块（三类能力）

### 7.1 查询溯源主流程

即第 4 节描述的核心流程（含校验返工循环）。

### 7.2 KB 初始化 skill

KB 初始化是**可选动作、不设上限**。当用户尚无知识库（或希望补充）时，可建库：

- **代码来源**：
  - 研发用户：基于**本地仓库**；
  - 非研发用户：经 **GitHub MCP** 拉远端仓库；
  - **可覆盖多仓**：多仓场景下可对每个配置了的仓库分别初始化。
- **入口点**：以 **RESTful 接口定义 + Kafka 消费者**为入口点。
- **建库方式**：沿这些入口类、以及其**调用链路上的类**的**提交记录 + Jira**，做**粗粒度**建库。
- **范围与上限**：**默认初始化全部入口点**，同时支持用户**按需 / 指定范围**初始化（例如仅某服务、某模块）；**不设硬性 token / 时间上限**，由用户控制范围。
- **知识自增长**：后续查询时按需做**细粒度沉淀**——终局**权威结论**经 `/cook` 写回 `queries/`，同类问题二次查询成本趋近于零；此外（优化B）code-analyst / repo-tracer / jira-tracer 在调查中产出的**增量发现**（KB 偏差校正、KB 未覆盖的入口/调用链、新 commit/工单线索、业务原因因果链等）由 dongmei-ma 终局归并、kb-keeper `append` 写 `modules/` / `entrypoints/`（与 `queries/` 权威结论隔离），使知识库逐步细粒度化。
- **KB 可信度审视（优化B）**：因 KB 多为粗粒度建库、可能滞后于代码演进，code-analyst 拿到 KB 线索后**先读实际代码再比对**，给出匹配度（一致 / 部分覆盖 / 过时 / 矛盾 / 未命中）与逐条偏差，**以代码为准**——既帮助 synthesizer/evidence-verifier 理解本次 KB 线索的可信度，又把校正后的事实经增量沉淀回流 KB，形成「审视→校正→回流」的闭环。KB 偏差不视为结论证据不足（见 §4.1 step8 红线）。

### 7.3 引导 / 配置 skill

- 带用户完成 **MCP 凭据等配置**（Jira / GitHub，二期 Figma）。
- **适配 Windows / macOS**，实现一步引导式配置，达到「开箱即用」。

### 7.4 双源切换逻辑（代码来源）

**过时判定按「被检索到的相关代码」粒度进行，而非整仓比较**：仅当某次查询命中的那段代码，其远端版本比本地新时，才就该段询问用户。

| 本地仓库状态（针对被检索到的相关代码） | 行为 |
| --- | --- |
| 无本地仓库（态A） | **全程 GitHub MCP**（远端模式），`code-analyst` 经 `repo-tracer` 取代码内容与远端提交历史 |
| 有本地仓库，且相关代码段不过时（态B） | 使用**本地**仓库：`code-analyst` 直读本地代码内容，并**经 Bash 直读本地 git 历史**作本地 git 证据片段附给 `repo-tracer`；`repo-tracer` 信任采用、统一收口产出提交时间线并抽工单号（未附则 repo-tracer 自取兜底）。**本地 git 不经 GitHub MCP**（优化A：本地 git 读取权 code-analyst/repo-tracer 共享，仅远端 GitHub MCP 独占 repo-tracer） |
| 有本地仓库，但相关代码段的远端版本更新（态C） | **就该段代码询问用户**是否经 GitHub MCP 取最新（非整仓比较；dongmei-ma 唯一询问者） |

> 多仓场景：上述判定按每个涉及的仓库分别进行；repo-tracer 据 code-analyst 的 repo+模块映射路由到对应本地仓库或 GitHub MCP 实例。
> **优化A 价值**：态B 本地非过时仓由 code-analyst 一次性直读代码内容 + 本地 git 历史，repo-tracer 免重复跑 git log（减少往返），同时本地 git 不触碰远端凭据、独占边界仅收窄到远端 GitHub MCP，归属更精确。

---

## 8. 技术栈与 core-ng 识别约定

### 8.1 参考仓库与技术栈

参考仓库：`D:\dev_repository\hdr-delivery-project`

- **Java 25** + **Gradle（Kotlin DSL）**
- **core-ng**（**开源框架**，Apache-2.0，**非 Spring Boot**；官方仓库 `https://github.com/neowu/core-ng-project`，含 wiki 与 DeepWiki 可供参考）
- 存储：**MongoDB（主）** / MySQL / ES
- 消息：**Kafka**
- 架构：多模块微服务

### 8.2 core-ng 识别约定（首版专攻 core-ng；规则集中一处、可扩展）

| 识别对象 | 约定标志 |
| --- | --- |
| **REST 入口** | `*-interface` 模块中的 `XXWebService` 接口（`@GET/@POST/@Path/@PathParam`），实现在 `{service}/web/XXWebServiceImpl`；或 `Controller.execute(Request)` + `http().route(...)` |
| **Kafka 入口** | 实现 `MessageHandler<T>` 的类（**非** `@KafkaListener`），注册在 `{Service}App.bindSubscribe()` |
| **调用链** | Controller / Handler → Service → QueryService / OperationService → Repository / MongoCollection → Domain，依赖通过 `@Inject` + `Module` 装配 |

### 8.3 设计约束（重要）

- **core-ng 是开源框架**（官方 wiki / 源码 / DeepWiki 可查），识别应**双重落地**：既依据**官方约定**（wiki / 源码中的框架惯例），又结合**目标仓库的实际标志**互相印证，以降低不确定性；
- 仍保留底线原则：**以代码中的实际标志为准，不空想惯例**——当官方约定与目标仓库实际写法不一致时，以目标仓库实际代码为准；
- 识别规则**集中在一处**维护，便于后续扩展到其他框架/技术栈。

---

## 9. 外部依赖与 MCP

| 依赖 | 类型 | 用途 | 凭据 / 备注 |
| --- | --- | --- | --- |
| 本地知识库（Obsidian Vault + Knowlery 插件） | 核心 | 代码模块定位线索；结论持久化 | 需初始化目录；边界唯一经 `kb-keeper` 读写（三道防线，见 §6.2）；**Knowlery 是 Obsidian 插件、无独立编程 API**，集成走 obsidian CLI + Knowlery 技能 `/ask` `/cook` |
| **Jira MCP** | 核心 | 工单详情与业务原因 | 选型 **`@aashari/mcp-server-atlassian-jira`**（通用 HTTP 透传型）；需 JIRA URL / 邮箱 / API Token；配置于共享 `.mcp.json`，`jira-tracer` L1 白名单仅授予 **`mcp__jira__jira_get`（只读）** |
| **GitHub MCP（远端）** | 核心 | 非研发用户取代码 + 远端提交历史；远端模式代码来源 | 选型 **GitHub Copilot 托管 MCP**：`https://api.githubcopilot.com/mcp/`；**每个 git repo 配置一个独立实例（独立 GitHub token）**，全部实例配置于共享 `.mcp.json`，其 `mcp__github-*` 工具经 **`repo-tracer` 边界独占（仅远端，三道防线，见 §6.2）** |
| 本地 Git 历史 | 核心（本地模式） | 演变时间线与变更溯源 | 依赖完整历史，不能是 shallow clone；多仓时每仓各一份；**读取权 `code-analyst` 与 `repo-tracer` 共享（经 Bash 直读、非独占；态B code-analyst 直读附给 repo-tracer 收口，优化A）**——独占只针对远端 GitHub MCP |
| **Figma MCP** | **二期** | UI 设计上下文与视觉演变 | 需 OAuth；涉及 UI 且用户提供 Figma 链接时触发；缺失不影响核心功能 |

- **MCP 与 skills 统一从项目级共享配置加载**（共享 `.mcp.json` / 项目级 `.claude/skills/`）；teammate 形态下 agent frontmatter 的 `mcpServers` / `skills` 字段不生效（见 §6.4、附录 B）。
- 归属约束（**远端** GitHub MCP 独占 repo-tracer〔本地 git 共享，优化A〕、KB 读写独占 kb-keeper、dongmei-ma 不直连源等）经**三道防线**保证：**L1 `tools` 白名单 + 每 agent 显式边界声明 + evidence-verifier 校验**——属边界约束而**非物理隔离**；L1 屏蔽机制已由真实 CLI 正面佐证、live 端到端演示待部署环境（TC-7.6），详见 §6.2 诚实声明。
- 凭据由**用户自填**、由**引导 skill** 协助完成；全部 `${VAR}` 环境变量化、配置零明文（每仓 server `github-<repoSlug>`，token 变量 `${DMSEEK_GH_TOKEN_<REPO_SLUG_UPPER>}`，统一前缀 `DMSEEK_`，见附录 B）。

---

## 10. 交付物与范围

### 10.1 交付物

一个**可导入的 Claude Code agent team 配置包**（7 个平级 teammate + 共享配置），包含：

- 角色定义（`.claude/agents/`，7 个首版 agent；每个含 ① `tools` 白名单（L1）+ ② `## 职责范围 / ## 允许使用的 MCP 服务 / ## 边界约束` 三段固定区块（声明层），实现三道防线归属约束；**不依赖** frontmatter 的 `mcpServers`/`skills`）
- 所需 **skills**（项目级 `.claude/skills/` 共享加载：KB 初始化 skill、引导/配置 skill、synthesizer 分析方法 skill 等）
- **共享 MCP 配置占位**（共享 `.mcp.json`：Jira / N×GitHub；二期 Figma；凭据 `${VAR}` 环境变量化、零明文）
- **文档与测试**（含三道防线诚实声明：独占 = L1 白名单 + 边界声明 + evidence-verifier 校验，**非物理隔离**，L1 屏蔽机制已由真实 CLI 正面佐证、live 端到端演示待部署环境 TC-7.6，见 §6.2、附录 B）
- 跨 **Windows / macOS** 开箱即用（含一步引导式配置）

### 10.2 范围

| 范围 | 首版 | 二期 |
| --- | --- | --- |
| 角色 | 7 个平级 teammate（dongmei-ma 为协调者 / kb-keeper / code-analyst / repo-tracer / jira-tracer / synthesizer / evidence-verifier）；非 subagent 父子委派 | + `design-tracer` |
| MCP | Jira（核心）、GitHub（核心） | Figma（OAuth） |
| 技术栈识别 | core-ng（专攻） | 可扩展至其他框架 |
| 场景 | 场景 1~8 | 场景 9（设计实现对齐，依赖 Figma） |
| 平台 | Windows + macOS | — |

---

## 11. 约束、假设与开放问题

### 11.1 约束（来自需求基线，硬性）

- 引擎仅 **Claude Code + Anthropic API**，不引入其他 LLM。
- 产物是 **Claude Code 成品 agent team 配置包**（7 个平级 teammate + 共享配置），**非自建框架、非 subagent 父子委派**（用户裁决，路径 B）。
- **运行形态 = agent team teammate**：经共享任务列表 + 消息协作；MCP/skills 从共享配置加载（共享 `.mcp.json` / 项目级 `.claude/skills/`），agent frontmatter 的 `mcpServers`/`skills` 字段不生效（见 §6.4、附录 B）。
- **以代码为唯一事实基准**；结论必须可回挂出处。
- **独占 = 双层边界 / 三道防线**（用户最终裁决，维持路径 B）：**L1 tools 白名单**（repo-tracer 仅 `mcp__github-*`、jira-tracer 仅 `mcp__jira__jira_get` 只读、kb-keeper 仅 KB/obsidian、dongmei-ma 不含源类 `mcp__`、其余按各自域）+ **每 agent 显式边界声明**（`## 职责范围 / ## 允许使用的 MCP 服务 / ## 边界约束`，硬性禁调领域外 MCP）+ **evidence-verifier 校验层**（标记边界违规）。属边界约束、**非物理隔离**；**L1 屏蔽机制已由真实 CLI 正面佐证（`tools` 白名单包含式、`mcp__` 受其管辖），live 端到端演示待部署环境（TC-7.6）——机制已佐证 ≠ live 已坐实**；交付文档须诚实声明，**不得写「物理隔离/已完成 live 坐实/已生效」**（见 §6.2、附录 B）。
- core-ng 识别**必须基于代码实际标志**，不得猜测框架惯例。
- 跨 Windows / macOS。

### 11.2 假设（待确认即转为需求）

- **输出语言：默认产出中文报告，英文版按需/附随提供**（系统支持中英双语，见 4.3；dongmei-ma 默认中文）——原「全程中文」假设由 O9 结论细化为「默认中文 + 可选英文」。
- 知识库目录结构沿用 vault 既有约定（结论写入 `queries/`）。
- 「至少 5 agent 并发」由首版 7 角色协作满足（多数为依赖链式协作，非全部同时并行）。

### 11.3 已定结论（用户已答复全部 10 项）

> 以下为用户对 v0.1 开放问题的最终答复，已同步到对应章节。

| # | 议题 | 结论 | 落到章节 |
| --- | --- | --- | --- |
| O1 | Knowlery 形态与集成 | Knowlery 是 **Obsidian 插件、无独立编程 API**。kb-keeper 集成 = obsidian CLI（search/read/create/append）+ Knowlery 技能 `/ask`（检索线索带引用）+ `/cook`（按 SCHEMA 编译结论沉淀至 `queries/`） | 6.1、9 |
| O2 | 过时判定粒度 | 按**「被检索到的相关代码」粒度**判断——该段代码远端比本地新时就该段询问用户，**非整仓比较** | 7.4 |
| O3 | 工单号格式 | 固定格式 `[A-Z]+-\d+`（本仓 `DELI-\d+`），位于 **commit subject 开头（冒号分隔）**；做成**可配置正则**、默认此式，**容错无号提交** | 6.1（repo-tracer） |
| O4 | 置信度量纲 | **离散三级（高/中/低）**：三源齐备=高 / 缺 jira 或仅 git=中 / 主要推断=低 | 4.1、4.3 |
| O5 | 返工上限与降级 | **最多 2 轮发散返工**；仍不足则**降级交付并明确声明「证据不足」+ 标注缺口** | 4.1、4.2 |
| O6 | 多仓库支持 | **支持跨多仓查询**。**一个 GitHub MCP 服务 ↔ 一个 git repo**（各自独立 token）；repo-tracer 管理 **N 个按仓库划分的 MCP 实例**；由 kb-keeper 线索 + code-analyst 定位映射到具体 repo+模块 | 6.1、6.2、7.2、7.4、9 |
| O7 | KB 初始化范围 | **可选动作、不设上限**；默认初始化全部入口点，支持按需/指定范围初始化 | 7.2 |
| O8 | MCP 选型 | Jira MCP = `@aashari/mcp-server-atlassian-jira`；GitHub MCP = GitHub Copilot 托管 `https://api.githubcopilot.com/mcp/`（每仓一实例 + 独立 token） | 9 |
| O9 | 输出语言 | **默认中文，英文按需/附随提供**（系统支持双语；KB 沉淀中文+英文摘要） | 4.3、6.1（dongmei-ma）、11.2 |
| O10 | Figma 触发（二期） | 涉及 UI 且用户提供 Figma 链接时触发，不阻塞主流程 | 5、9、10 |

### 11.4 剩余风险

- **多仓配置复杂度**：每仓一个 GitHub MCP 实例 + 独立 token，仓库数量多时配置与凭据管理负担上升——引导/配置 skill 需妥善处理批量配置与凭据安全（基础白名单 + 用户自填）。
- **跨仓定位准确性**：一次查询涉及哪些仓库由 KB 线索 + code-analyst 定位推导，跨服务隐性调用可能遗漏仓库——依赖 KB 质量与 evidence-verifier 的校验返工兜底。
- **core-ng 识别**：虽为开源、有官方语料（风险较 v0.1 下降），但目标仓库可能有偏离官方约定的写法；坚持「以代码实际标志为准」并建议设计阶段由 code-analyst 对参考仓库 `hdr-delivery-project` 做真实样本核验。
- **双语成本**：默认仅产出中文报告，英文按需/附随生成，故常态开销可控；KB 沉淀采「中文 + 英文摘要」，具体落库形式（摘要粒度、是否随结论同写）需在设计阶段明确。
- **L1 屏蔽机制已正面佐证、live 演示待部署环境（v0.4.1）**：teammate 形态下 MCP 实例对全队共享加载，per-agent MCP 独占在当前 Claude Code **仅 L1（tools 白名单）一个原生机制**；`deniedMcpServers` 是组织/会话级一刀切、不能 per-agent（会误伤），不可用。真实 `claude` CLI 实测已**正面佐证** L1 机制（`tools` 白名单为包含式、`mcp__` 受其管辖，见附录 B.3）；**live 端到端负向演示（无权 teammate 试调 live MCP 被挡）待部署环境**（TC-7.6），机制已佐证 ≠ live 已坐实。纵深防御（采用三道防线而非单押 L1 的理由）：**声明层**（每 agent `## 边界约束` 硬性禁调领域外 MCP）+ **校验层**（evidence-verifier 标记边界违规）使边界即便在 L1 意外失效时仍**清晰、可审计**；交付文档诚实声明（不得写「已完成 live 坐实/已生效」）。
- **白名单配置错误风险**：L1 白名单若误含领域外 `mcp__` 工具会突破独占且运行期可能不报错——由 critic（T7）设计期校验白名单 + 声明层一致性，evidence-verifier 运行期兜底。
- **形态机制依赖官方行为（v0.4）**：「frontmatter `mcpServers`/`skills` 在 teammate 形态下不生效、须走共享配置」「无 per-agent MCP 独占机制」等前提已由官方文档双向核实（附录 B），但属对 Claude Code 当前行为的依赖；若官方实现变更需复核 §6.2、§6.4 与骨架（T8）。

---

## 附录 A：需求基线相对来源 HTML 的主要演进

> 凡冲突以基线为准。记录差异以便追溯。

| 维度 | 来源 HTML | 需求基线（权威） |
| --- | --- | --- |
| 角色数量 | 5 个 | **7 + 1**（首版 7，二期 Figma） |
| 角色 id | mdm-lead / kb-locator / git-historian / jira-tracer / design-tracer | **dongmei-ma / kb-keeper / code-analyst / repo-tracer / jira-tracer / synthesizer / evidence-verifier**(+design-tracer) |
| 代码定位 | kb-locator 仅给路径/类（信息源=KB） | **拆分**：kb-keeper 给线索（不读源码）+ code-analyst 定位并**解读**代码 |
| 代码来源 | 默认本地（Git 本地历史核心） | **双源**：本地 / 远端（GitHub MCP），含过时判定与用户决策 |
| GitHub MCP | 可选（补充 PR/Review） | **核心**，独占于 repo-tracer，非研发用户取代码主路径 |
| 校验机制 | 无显式校验 | 新增 **evidence-verifier + 置信度 + 发散返工循环** |
| 综合环节 | 马冬梅汇总 | 独立 **synthesizer** 角色，分析方法沉淀为 skill |
| 建库能力 | 「需预先初始化」 | 新增 **KB 初始化 skill**（入口点 + 调用链粗粒度建库，知识自增长） |
| 配置能力 | 未提 | 新增 **引导/配置 skill**，跨 Win/macOS 一步配置 |
| 技术栈 | 未指定 | **core-ng**（Java 25 / Gradle KTS / Mongo / Kafka），开源框架、官方+目标仓库双重落地识别 |
| 形态 | 「系统」 | 明确为 **Claude Code 成品 agent team 配置包**；**v0.4 进一步定性为 agent team teammate 形态**（7 平级 teammate + 共享配置，非 subagent 父子委派） |
| 角色协作模型 | 隐含「马冬梅汇总」式主从 | v0.1~v0.3 隐含 subagent 父子委派；**v0.4 修订为平级 teammate + 共享任务列表/消息**（dongmei-ma 为协调者非父） |
| 独占机制 | 未涉及 | v0.1~v0.3 隐含物理独占；v0.4 修订为策略级独占（tools 白名单）；**v0.4.1 经用户最终裁决定为「双层边界 / 三道防线」**：L1 白名单 + 每 agent 显式边界声明 + evidence-verifier 校验；非物理隔离，L1 屏蔽机制已由真实 CLI 正面佐证、live 端到端演示待部署环境（TC-7.6）；**v0.4.2 独占口径收窄**：独占仅针对**远端 GitHub MCP**，**本地 git 历史读取权 code-analyst/repo-tracer 共享**（优化A） |
| 本地 git 历史读取 | 隐含归 repo-tracer（含本地） | **v0.4.2**：态B 本地非过时仓 code-analyst 可经 Bash 直读本地 git 历史作证据附给 repo-tracer 收口（本地 git 共享、非独占；远端历史仍经 repo-tracer 的 GitHub MCP，优化A） |
| KB 可信度与增量沉淀 | 未涉及 | **v0.4.2（优化B）**：code-analyst 审视 KB 与实际代码匹配性（kbAlignment，以代码为锚）；code-analyst/repo-tracer/jira-tracer 增量发现经 dongmei-ma 终局归并、kb-keeper append 写 modules/entrypoints（与 queries/ 权威结论隔离）；KB 偏差不下调置信度 |
| 仓库数 | 隐含单仓（本地 git） | **支持多仓**：一个 GitHub MCP 实例 ↔ 一个 repo，repo-tracer 管理 N 个实例（v0.2 新增） |
| 输出语言 | 全程中文 | **默认中文 + 英文按需/附随**（v0.2 修订） |
| GitHub MCP 选型 | 未指定 | GitHub Copilot 托管 MCP（v0.2 明确）；Jira MCP = `@aashari/mcp-server-atlassian-jira` |
| 只读政策 | 未涉及 | **v0.4.3**：全局只读政策——代码/Git/GitHub/Jira 全部只读，仅 `git fetch` + KB 写例外（§6.5 / runtime-spec §4.4） |
| synthesizer 输出 | 单层综合结论 | **v0.4.3**：双层输出——`executiveSummary`（非技术人员可读摘要）+ 完整结论（§4.1 step7 / §4.3） |
| agent prompt 体积 | 85+ 行 | **v0.4.3**：code-analyst/repo-tracer 精简至 ~30 行（保留职责+约束+声明三段式） |

---

## 附录 B：运行形态与独占机制修订记录（subagent 假设 → teammate 形态 → 双层边界）

> 记录形态修订（v0.4）与独占口径定稿（v0.4.1）的理由、官方核实依据与对实现的约束，便于追溯。

### B.1 修订理由

- **v0.1~v0.3 的隐含假设**：早期 PRD 将 dongmei-ma 视为「编排/调度」角色，隐含 **subagent 父子委派**模型（主 agent 用 Task 工具逐个 spawn 子 agent、独占其返回），并隐含「独占=物理隔离」（某 MCP 只在某 agent 进程内可达）。
- **用户裁决 v0.4（路径 B）**：交付物应是**一支真正的 agent team**——7 个平级 teammate + 一套共享配置，运行形态为 **agent team teammate**（非 subagent 父子委派）。这更贴合「可导入、开箱即用的成品 team」定位，且与本开发队自身的协作模型一致（dongmei-ma ≈ tech-lead 式协调者）。
- **用户最终裁决 v0.4.1（独占口径，维持路径 B 不切 A）**：接受共用 `.mcp.json`；但要求**每个 agent 显式声明「职责范围 + 允许使用的 MCP 服务」、明确禁调领域外 MCP**。据此独占定稿为**双层边界 / 三道防线**（见 §6.2），不单押 L1（纵深防御；L1 机制本身已由真实 CLI 正面佐证、live 演示待部署环境）。

### B.2 官方核实结论（双向核实）

teammate 形态下的三条机制性事实（影响独占与配置落地）：

1. **MCP 从共享配置加载**：MCP 实例由项目级共享 `.mcp.json`（及 project/user settings）加载，对全队 teammate 共享；**agent frontmatter 的 `mcpServers` 字段在 teammate 形态下不生效**。
2. **skills 从项目级目录加载**：skills 由项目级 `.claude/skills/`（project/user settings）加载；**agent frontmatter 的 `skills` 字段同样不生效**。
3. **无 per-agent MCP 独占原生机制**：per-agent MCP 独占在当前 Claude Code **仅 `tools` 白名单（L1）一个原生机制**。`deniedMcpServers` / `disabledMcpjsonServers` / `permissions.deny mcp__*` 均为**组织 / 会话级一刀切、不能 per-agent**（对某 agent deny 会误伤合法使用方），故**不采用**作 per-agent 兜底。

> 推论：源类 MCP 对全队共享加载，独占无法靠物理隔离实现；L1 `tools` 白名单是唯一**技术层**机制，其屏蔽机制**已由真实 CLI 正面佐证（见下 B.3）**（live 端到端演示待部署环境），仍以**声明层 + 校验层**补强构成三道防线（纵深防御）。

### B.3 L1 屏蔽机制状态（TC-7.6：机制已正面佐证，live 演示待部署环境）

- **真实 CLI 实测正面佐证（2026-06-12，`claude` CLI 2.1.165 当场实测）**：以 `claude -p --agent repo-tracer --strict-mcp-config --mcp-config <临时 github 配置>` 启动真实会话，该会话可用工具集 = **精确的 `[Bash, Read, SendMessage]`（非默认全量工具集）**——证实真实 Claude Code **强制 agent frontmatter 的 `tools` 白名单、白名单为「包含式」、`mcp__` 工具受同一白名单管辖**（repo-tracer 须**显式声明** `mcp__github-...` 方得调用）。逻辑推论：未声明 `mcp__` 的 agent（synthesizer / dongmei-ma 等）运行时无任何 `mcp__` 工具 = **L1 屏蔽成立**。
- 此实测**推翻了**早先 harness 探针「白名单可能未生效」的疑虑——那次是中途 spawn 路径未施加白名单（teammate 仍拿全量工具），属 spawn 路径问题、**非引擎不支持**；真实 CLI 下白名单确实生效。
- **仍待补 = 「live MCP 工具存在却被白名单挡住」的端到端负向演示**：本会话连不上 live MCP（GitHub Copilot 托管 MCP 在 headless 下未连上、本地 MCP 包被权限策略拦截），故该帧留**部署环境**——它是上述已证机制的**直接推论**，非新的未知。列为**测试项 TC-7.6，归 T16（验证）/ qa**（用户侧自验步骤见 `.claude/README.md` 与 `验证-TC-7.6-独占运行时验证步骤.md`）。
- **诚实声明硬性口径**：独占 = L1 白名单 + 每 agent 显式边界声明 + evidence-verifier 校验；**L1 屏蔽机制已由真实 CLI 正面佐证、live 端到端演示待部署环境**——**机制已佐证 ≠ live 已坐实**；**不得写「物理隔离 / 已完成 live 坐实 / 已生效」**。审慎兜底分支：若 live 演示在部署环境意外证伪 L1，则当前 Claude Code 无 per-agent MCP 硬独占，独占降级为**软隔离**（声明层 + evidence-verifier 兜底）并升级用户决策——但边界仍清晰可审计。

### B.4 对实现的约束（落到 T8 骨架及相关任务）

- 7 个 agent 定义置于 `.claude/agents/`，**每个含两段机制**：① `tools` 白名单（L1，只含本域工具）；② 固定声明区块 `## 职责范围 / ## 允许使用的 MCP 服务 / ## 边界约束`（声明层，硬性禁调领域外 `mcp__`、跨域经任务列表/消息向 owner agent 请求）。
  - `repo-tracer`：L1 含 `mcp__github-*`（全部 GitHub MCP 实例工具）；其余 agent 不含。
  - `jira-tracer`：L1 仅 `mcp__jira__jira_get`（**只读**，`@aashari` server 为通用 HTTP 透传型，见 KB「dm-seek Jira MCP 接口」结论）。
  - `kb-keeper`：仅 KB/obsidian 工具（obsidian CLI / Knowlery 技能，**非 `mcp__`**）；不含任何源类 `mcp__`。
  - `dongmei-ma` / `synthesizer` / `evidence-verifier`：**不含任何源类 `mcp__`**；`code-analyst` 仅本地代码读取工具。
- **校验层**：`evidence-verifier` 实现含「标记结论引用声明范围外工具/数据来源」的边界违规检查（与置信度同环，运行期兜底）。
- **MCP 工具引用名约定**：`mcp__<serverName>__<toolName>`；整服务前缀 `mcp__<serverName>`。
- **MCP 配置占位**统一写入共享 `.mcp.json`；每仓 GitHub server 命名 `github-<repoSlug>`，token 经环境变量 `${DMSEEK_GH_TOKEN_<REPO_SLUG_UPPER>}` 注入（凭据零明文，统一前缀 `DMSEEK_`）。
- **skills**（KB 初始化、引导/配置、synthesizer 分析方法等）统一置于项目级 `.claude/skills/`；**不**写入 agent frontmatter。
- 此规范为 **T8 骨架 + #9~#15 各 agent 实现**的强制要求；TC-7.6 的 **live 端到端演示**由 **T16 / qa** 在部署/运行环境补做（L1 机制本身已由真实 CLI 正面佐证，见 B.3）。
