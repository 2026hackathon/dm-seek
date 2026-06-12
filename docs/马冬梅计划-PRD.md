# 马冬梅计划 — 产品需求文档（PRD）

| 项目 | 内容 |
| --- | --- |
| 产品名 | 马冬梅计划（dm-seek） |
| 定位 | 面向研发全角色的「代码现实 × 需求演进」追溯系统 |
| 形态 | 可导入、开箱即用的 **Claude Code 成品 team**（非自建框架） |
| 引擎 | Claude Code，直连 Anthropic API（仅 Claude） |
| 运行环境 | 本地 CLI 进程，跨 Windows / macOS |
| 文档版本 | v0.3（已回填 10 项答复并校正 O9 输出语言口径，待用户最终确认） |
| 日期 | 2026-06-12 |
| 负责人 | architect |
| 状态 | 待用户确认（确认前不进入设计/实现，不引入 critic） |

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

马冬梅计划是一套 **Claude Code 成品 team**：以 Claude Code 为运行引擎，交付一份可导入、开箱即用的团队配置（角色定义 `.claude/agents/`、所需 skills、MCP 配置占位、文档与测试）。它**不是**一个自建的 agent 框架，也不引入 Claude 以外的 LLM。

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
- 用户以自然语言提问；team 内部多 agent 协作完成溯源；最终由编排者交付报告。
- 凭据（Jira / GitHub / Figma 的 URL / 邮箱 / Token 等）由用户自填，引导 skill 协助完成配置。

---

## 4. 核心查询溯源流程（含校验返工循环）

### 4.1 流程步骤

1. 用户提出一句自然语言疑问。
2. **dongmei-ma** 解析疑问，拆解为子任务并驱动调度。
3. **kb-keeper** 查询知识库（KB），给出线索（模块、路径、核心类等候选）。
4. **code-analyst** 据 KB 线索**定位具体代码并解读**（core-ng）。
   - 本地有仓库：直接读本地文件；
   - 无本地仓库（远端模式）：经 **repo-tracer** 取代码内容；
   - KB 未命中：回源码兜底（直接在代码中搜索定位）。
5. **repo-tracer** 给出**提交时间线**，并从 commit 信息中**抽取 Jira 工单号**。
6. **jira-tracer** 经 **Jira MCP** 取对应工单的**业务原因**与因果脉络。
7. **synthesizer** 综合 code + git + jira 三源，产出**结论**。
8. **evidence-verifier** 校验证据充分性并给出**置信度（离散三级：高 / 中 / 低）**：
   - 判据：三源（code + git + jira）齐备且互相印证 = **高**；缺 Jira 业务原因、或仅有 git 时间线 = **中**；结论主要依赖推断、缺直接出处 = **低**。
   - **充分** → dongmei-ma 交付报告；kb-keeper 把结论**沉淀回 KB（`queries/`）**。
   - **不足** → dongmei-ma **发散重派**、扩大搜索范围后重新综合（回到第 4~7 步），形成**校验返工循环**。
   - **返工上限：最多 2 轮发散返工**。两轮后仍不足时，**降级交付**：照常出报告，但**明确声明「证据不足」并标注具体缺口**（缺哪一源/哪一环），不无限循环、不臆造结论。

### 4.2 流程图

```
            用户一句自然语言疑问
                     │
                     ▼
            ┌──────────────────┐
            │   dongmei-ma     │  解析疑问 / 拆解任务 / 调度
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
            │ 时间线+抽工单号   │  (独占 GitHub MCP)
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

- **当前实现状态**（代码现实）
- **演变时间线**（Git，含关联工单号）
- **根因解释**（Jira 业务原因）
- **置信度**（evidence-verifier 评估，高 / 中 / 低；证据不足时显式声明并标注缺口）
- **语言：默认产出中文报告**——dongmei-ma 默认以**中文**交付报告；系统仍支持中英双语，**英文版按需/附随提供**（非默认每次产出，由用户请求或在需要时生成）。
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

### 6.1 角色清单

| # | id | 职责 | 信息源 / 归属 | 阶段 |
| --- | --- | --- | --- | --- |
| 1 | `dongmei-ma` | 编排、用户接口、拆解任务、驱动校验返工循环、最终交付（**默认产出中文报告**，英文版按需/附随提供） | 编排层，不直连信息源 | 首版 |
| 2 | `kb-keeper` | **唯一 Obsidian 读写口**：从 KB 给线索 + 结论沉淀回写；**不读源码**。集成方式：obsidian CLI（search / read / create / append）+ Knowlery 技能 `/ask`（检索线索、带引用）+ `/cook`（按 SCHEMA 编译结论沉淀至 `queries/`） | 知识库（Obsidian Vault + Knowlery 插件，经 obsidian CLI / Knowlery 技能，无独立编程 API） | 首版 |
| 3 | `code-analyst` | 据 KB 线索**定位具体代码 + 解读代码**（core-ng）；KB 未命中回源码兜底；KB 初始化时遍历入口点/调用链的执行者；将定位结果**映射到具体 repo + 模块**，告知 repo-tracer 涉及哪些仓库 | 代码内容（本地直读 / 远端经 repo-tracer） | 首版 |
| 4 | `repo-tracer` | Git / GitHub 仓库网关，**独占全部 GitHub MCP 实例**；本地读 git 历史，远端经 GitHub MCP 取代码内容+提交历史；**管理 N 个按仓库划分的 GitHub MCP 实例（一个 MCP 服务 ↔ 一个 git repo，各自独立 token），支持一次查询横跨多仓**；**始终从 commit subject 抽取 Jira 工单号**（默认正则 `[A-Z]+-\d+`，本仓 `DELI-\d+`，可配置，容错无号提交） | 本地 Git / 多个 GitHub MCP 实例 | 首版 |
| 5 | `jira-tracer` | 经 **Jira MCP** 取工单业务原因与多工单因果脉络 | Jira MCP | 首版 |
| 6 | `synthesizer` | 综合 code + git + jira → 结论（对应 9 类场景：质量评估 / 影响范围 / 变更脉络等）；**分析方法沉淀为可复用 skill** | 上游三源产物 | 首版 |
| 7 | `evidence-verifier`（critic 角色） | 校验每条结论是否挂着 **代码 / commit / 工单**出处 + 输出**置信度** + 不足时**触发发散返工** | 上游全部产物 | 首版 |
| 8 | `design-tracer` | Figma 设计追溯：设计上下文与视觉演变 | Figma MCP | **二期** |

### 6.2 关键归属约束（双源）

- **全部 GitHub MCP 实例独占于 `repo-tracer`**：其他 agent 不直接调用任何 GitHub MCP。多仓场景下每个 git repo 对应一个独立 GitHub MCP 实例（独立 token），均由 repo-tracer 统一管理与路由。
- **远端模式**下，`code-analyst` 需要的代码内容**经 `repo-tracer` 取得**，自身不直连 GitHub MCP。
- **跨仓查询**：一次查询可能涉及多个仓库；由 `kb-keeper` 的线索与 `code-analyst` 的定位**映射到具体 repo + 模块**，再由 `repo-tracer` 路由到对应的 GitHub MCP 实例 / 本地仓库。
- **Obsidian 知识库读写唯一收口于 `kb-keeper`**：其他 agent 不直接读写 KB。
- `dongmei-ma` 是编排与用户接口层，不直连任何信息源。

### 6.3 角色协作流程图

见 4.2 流程图。校验返工循环由 `dongmei-ma` 依据 `evidence-verifier` 的判定驱动。

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
- **知识自增长**：后续查询时按需做**细粒度沉淀**（结论写回 `queries/`），同类问题二次查询成本趋近于零。

### 7.3 引导 / 配置 skill

- 带用户完成 **MCP 凭据等配置**（Jira / GitHub，二期 Figma）。
- **适配 Windows / macOS**，实现一步引导式配置，达到「开箱即用」。

### 7.4 双源切换逻辑（代码来源）

**过时判定按「被检索到的相关代码」粒度进行，而非整仓比较**：仅当某次查询命中的那段代码，其远端版本比本地新时，才就该段询问用户。

| 本地仓库状态（针对被检索到的相关代码） | 行为 |
| --- | --- |
| 无本地仓库 | **全程 GitHub MCP**（远端模式），`code-analyst` 经 `repo-tracer` 取代码 |
| 有本地仓库，且相关代码段不过时 | 使用**本地**仓库 |
| 有本地仓库，但相关代码段的远端版本更新 | **就该段代码询问用户**是否经 GitHub MCP 取最新（非整仓比较） |

> 多仓场景：上述判定按每个涉及的仓库分别进行；repo-tracer 据 code-analyst 的 repo+模块映射路由到对应本地仓库或 GitHub MCP 实例。

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
| 本地知识库（Obsidian Vault + Knowlery 插件） | 核心 | 代码模块定位线索；结论持久化 | 需初始化目录；唯一经 `kb-keeper` 读写；**Knowlery 是 Obsidian 插件、无独立编程 API**，集成走 obsidian CLI + Knowlery 技能 `/ask` `/cook` |
| **Jira MCP** | 核心 | 工单详情与业务原因 | 选型 **`@aashari/mcp-server-atlassian-jira`**；需 JIRA URL / 邮箱 / API Token |
| **GitHub MCP** | 核心 | 非研发用户取代码 + 提交历史；远端模式代码来源 | 选型 **GitHub Copilot 托管 MCP**：`https://api.githubcopilot.com/mcp/`；**每个 git repo 配置一个独立实例（独立 GitHub token）**，**全部独占于 `repo-tracer`** |
| 本地 Git 历史 | 核心（本地模式） | 演变时间线与变更溯源 | 依赖完整历史，不能是 shallow clone；多仓时每仓各一份 |
| **Figma MCP** | **二期** | UI 设计上下文与视觉演变 | 需 OAuth；涉及 UI 且用户提供 Figma 链接时触发；缺失不影响核心功能 |

- 工具权限做**基础白名单**。
- 凭据由**用户自填**，由**引导 skill** 协助完成。

---

## 10. 交付物与范围

### 10.1 交付物

一个**可导入的 Claude Code 团队配置包**，包含：

- 角色定义（`.claude/agents/` 等，7 个首版 agent）
- 所需 **skills**（KB 初始化 skill、引导/配置 skill、synthesizer 分析方法 skill 等）
- **MCP 配置占位**（Jira / GitHub；二期 Figma）
- **文档与测试**
- 跨 **Windows / macOS** 开箱即用（含一步引导式配置）

### 10.2 范围

| 范围 | 首版 | 二期 |
| --- | --- | --- |
| 角色 | 7 个 agent（dongmei-ma / kb-keeper / code-analyst / repo-tracer / jira-tracer / synthesizer / evidence-verifier） | + `design-tracer` |
| MCP | Jira（核心）、GitHub（核心） | Figma（OAuth） |
| 技术栈识别 | core-ng（专攻） | 可扩展至其他框架 |
| 场景 | 场景 1~8 | 场景 9（设计实现对齐，依赖 Figma） |
| 平台 | Windows + macOS | — |

---

## 11. 约束、假设与开放问题

### 11.1 约束（来自需求基线，硬性）

- 引擎仅 **Claude Code + Anthropic API**，不引入其他 LLM。
- 产物是 **Claude Code 成品 team 配置包**，非自建框架。
- **以代码为唯一事实基准**；结论必须可回挂出处。
- **GitHub MCP 独占于 repo-tracer**；**KB 读写独占于 kb-keeper**。
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
| 形态 | 「系统」 | 明确为 **Claude Code 成品 team 配置包** |
| 仓库数 | 隐含单仓（本地 git） | **支持多仓**：一个 GitHub MCP 实例 ↔ 一个 repo，repo-tracer 管理 N 个实例（v0.2 新增） |
| 输出语言 | 全程中文 | **默认中文 + 英文按需/附随**（v0.2 修订） |
| GitHub MCP 选型 | 未指定 | GitHub Copilot 托管 MCP（v0.2 明确）；Jira MCP = `@aashari/mcp-server-atlassian-jira` |
