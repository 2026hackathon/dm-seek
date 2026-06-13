# 设计 — KB 初始化流程 + KB 读写集成形态（obsidian CLI + Knowlery /ask /cook）

| 项目 | 内容 |
| --- | --- |
| 文档 | design-kb-init-and-integration.md（设计/契约） |
| owner | tools-dev |
| 对应任务 | #5（设计期），下游依赖 #10 kb-keeper 实现、#15 KB-init skill 实现 |
| 依据 | 马冬梅计划-PRD.md v0.3（§4.1 主流程沉淀、§6.1 kb-keeper、§7.2 KB-init、§9 Obsidian 依赖、O1/O7/O9 结论）；core-ng 识别核验结论（见下 §2.1） |
| 软依赖 | task #2（core-ng 入口点/调用链识别规则，供建库遍历）—— 核验结论已坐实，见 §2.1 |
| 平台 | Windows + macOS |
| 状态 | 待 critic 审视 |

> 本文是 KB 初始化流程与 kb-keeper 集成形态的**权威契约**：建库遍历算法、多仓与双源代码来源、kb-keeper 唯一读写口的工具映射、KB 目录结构与沉淀 SCHEMA、知识自增长与中英摘要落库形式。SCHEMA 与 Knowlery 命令的精确字段为**可校准占位**，实现期由 kb-keeper owner 对照真实 Knowlery 插件定稿（见 §7）。

---

## 0. 关键结论（TL;DR）

1. **kb-keeper 是唯一 Obsidian 读写口**，集成面恰好两类、四 + 二个动作：obsidian CLI（`search` / `read` / `create` / `append`）+ Knowlery 技能（`/ask` 检索线索带引用、`/cook` 按 SCHEMA 编译结论沉淀至 `queries/`）。kb-keeper **不读源码**（读源码是 code-analyst 的事）。
2. **KB-init 是可选动作、不设硬性上限**：以 core-ng 的 REST 入口 + Kafka 入口为**遍历种子**，沿入口类及其**调用链类**收集「提交记录 + 关联 Jira 工单」做**粗粒度**建库。默认初始化全部入口点，支持按服务/模块限定范围。
3. **多仓分别初始化**：每个已配置仓库各跑一遍 init，KB 内按 repo 命名空间组织，互不串味。
4. **双源代码来源**：研发用户走本地仓库（code-analyst 直读）；非研发走 GitHub MCP（code-analyst 经 repo-tracer 取）。KB-init 不直接碰 MCP/源码——它**编排** code-analyst（取入口/调用链）+ repo-tracer（取 commit + 抽工单号）+ jira-tracer（取业务原因）的产物，由 kb-keeper 落库。
5. **知识自增长**：每次查询的结论经 `/cook` 按 SCHEMA 写回 `queries/`，**中文正文 + 英文摘要**（O9），同类问题二次查询近乎秒答。
6. **职责边界铁律**：KB-init 是一个 **skill**（task #15），不是一个 agent；它在 dongmei-ma 编排下调度既有 7 agent，**写库动作一律经 kb-keeper**，不旁路。

---

## 1. 角色与边界（谁碰 KB、谁碰源码）

| 动作 | 唯一执行者 | 经什么 |
| --- | --- | --- |
| 读/写 Obsidian KB | **kb-keeper** | obsidian CLI + Knowlery `/ask` `/cook` |
| 读源码、定位+解读（含遍历入口/调用链） | code-analyst | 本地直读 / 态B 本地 git 历史经 Bash / 远端经 repo-tracer |
| 取 commit 时间线 + 抽工单号（统一收口） | repo-tracer | 态B 本地 git 采用 code-analyst 提供片段（未附自取兜底） / 远端 GitHub MCP；抽工单号、多仓合并收口在 repo-tracer |
| 取工单业务原因 | jira-tracer | Jira MCP |
| 编排 KB-init / 查询全流程 | dongmei-ma | 调度上述 agent |

> KB-init skill 自身不读源码、不连 MCP、不写库；它是 dongmei-ma 驱动的一段**编排流程**，各专职动作落到对应 agent。这保证 PRD §6.2「KB 读写独占 kb-keeper」「GitHub MCP（远端）独占 repo-tracer」「dongmei-ma 不直连源」三条约束在建库路径上同样成立。注：本地 git 历史读取权 code-analyst/repo-tracer 共享（态B 经 Bash 直读本地仓），独占只针对远端 GitHub MCP。

---

## 2. KB 初始化流程（KB-init）

### 2.1 建库种子 = core-ng 入口点（依据 task #2 核验，已坐实）

> 软依赖 task #2 的核验结论已坐实（参考仓 `D:\dev_repository\hdr-delivery-project`），建库遍历直接据此：

- **REST 入口（种子A）**：`{service}-interface` 模块 `api/` 包下的 `*WebService` 接口（注解 import 自 `core.framework.api.web.service.*`：`@GET/@POST/@PUT/@PATCH/@DELETE/@Path/@PathParam`），实现 `{service}/web/*WebServiceImpl`，装配 `api().service(X.class, bind(XImpl.class))`。第二形态：`Controller` + `http().route(HTTPMethod.X, path, controller::method)`。
- **Kafka 入口（种子B）**：`implements MessageHandler<T>`（`core.framework.kafka.MessageHandler`，非 `@KafkaListener`），注册在 `{Service}App.bindSubscribe()` 的 `kafka().subscribe(Topic, Msg.class, bind(Handler.class))`。
- **调用链遍历**：入口类 → `@Inject`（`core.framework.inject.Inject`）注入的 Service（QueryService/OperationService/CreationService）→ Repository（`db().repository(X.class)`，MySQL 风格）/ Mongo（`config(MongoConfig).collection(X.class)` / `.view(X.class)`）→ Domain。**存储双形态都要覆盖**（以代码实际标志为准）。
- 框架版本可由 commit 定位（如 `DELI-4511:upgrade coreNG to 5.0.4`）。

> 识别规则的权威定义仍以 code-analyst 的 `design-core-ng-recognition.md`（task #2 产物）为准；本文只消费「入口点 + 调用链」这一遍历能力，不重复定义识别规则。

### 2.2 流程（单仓）

```
[KB-init skill, 由 dongmei-ma 编排，针对一个 repo]
  1. 范围确定
       默认：全部入口点；或用户指定（某 service / 某模块 / 某包）
  2. code-analyst：枚举范围内入口点（种子A REST + 种子B Kafka）
       → 对每个入口，沿调用链向下展开到 Service/Repository/Domain（粗粒度，深度可控）
       → 产出「入口 → 调用链类集合 → 所在 repo+模块」清单（粗粒度，不逐行解读）
  3. repo-tracer：对清单中的类/文件，取其提交记录（粗粒度：关键 commit、首次引入/最近修改）
       → 从 commit subject 抽 Jira 工单号（DELI-\d+，容错无号）
  4. jira-tracer：对抽到的工单号，取业务原因摘要（建库阶段取“标题+概述”级，不取全量评论）
  5. kb-keeper：把 (入口/模块/调用链 + commit 线索 + 工单线索) 经 /cook 按 INDEX-SCHEMA
       编译为粗粒度 KB 条目，写入该 repo 命名空间下的 modules/ 与 entrypoints/
  6. 幂等：已存在条目 → append/更新；不重复建。记录 init 元数据（时间、范围、commit HEAD）
```

> **粗粒度** = 建库阶段只落「入口点、模块归属、调用链骨架、关键 commit 与工单号、业务原因一句话」；逐行代码解读与细节留到查询时按需做、按需沉淀（§5 知识自增长）。

### 2.3 范围与上限（O7）

- **可选动作**：无 KB 也能查询（查询时 KB 未命中走源码兜底）；KB-init 是「先建好、后秒答」的可选加速。
- **默认全部入口点**；支持按需限定（`scope: service=delivery-task-v2` / `module=...` / `package=...`）。
- **不设硬性 token/时间上限**：由用户用 scope 控制范围；skill 给出进度与可中断点（按入口点分批），而非一把梭。

### 2.4 多仓（分别初始化）

- 对每个已配置仓库各跑一遍 §2.2，**KB 内按 repo 命名空间隔离**（见 §4 目录结构 `<repoSlug>/`）。
- repo+模块映射沿用 `design-mcp-config-shape.md` §2.3 的映射表；repo-tracer 据此路由到对应本地仓库或 GitHub MCP 实例。
- 跨服务隐性调用可能跨仓——建库阶段按「显式调用链」覆盖，跨仓隐性依赖由查询期 evidence-verifier 的发散返工兜底（PRD §11.4 已识别此风险）。

### 2.5 双源代码来源（建库期）

| 用户类型 | 代码来源 | 路径 |
| --- | --- | --- |
| 研发（有本地仓库） | 本地 | code-analyst 直读本地文件 |
| 非研发（无本地仓库） | 远端 | code-analyst 经 repo-tracer → GitHub MCP 取内容 |

> 建库期不做「过时判定」（那是查询期、按被检索代码段粒度的事，见 task #4）；建库就以当前可得版本为基线，并把 commit HEAD 记入 init 元数据，便于后续判定。

---

## 3. kb-keeper 集成形态（唯一读写口）

### 3.1 两类集成、动作映射

| 能力 | 机制 | 用途 | 读/写 |
| --- | --- | --- | --- |
| 全文/路径检索 | obsidian CLI `search` | 找候选模块/路径/类线索 | 读 |
| 取条目内容 | obsidian CLI `read` | 读已有 KB 条目正文 | 读 |
| 新建条目 | obsidian CLI `create` | 建库时落新条目骨架 | 写 |
| 追加 | obsidian CLI `append` | 向已有条目补充线索/增量 | 写 |
| 语义检索带引用 | Knowlery `/ask` | 查询期给 dongmei-ma/code-analyst 线索，**带来源引用** | 读 |
| 结论编译沉淀 | Knowlery `/cook` | 按 SCHEMA 把结论编译进 `queries/`（建库/查询沉淀） | 写 |

> 选择依据：obsidian CLI 适合**确定性的文件级**读写（建库骨架、append 增量）；Knowlery `/ask` 适合**语义检索 + 引用**（线索质量更高）；`/cook` 是 Knowlery 把非结构内容**按 SCHEMA 规整**落 `queries/` 的编译动作。kb-keeper 按场景择一，不混用导致写入格式漂移。

### 3.2 obsidian CLI 调用注意事项（硬约束，来自实地记录 [[obsidian-cli-invocation]]）

1. **二进制位置**：`D:\obsidian\Obsidian.com`（Windows）。kb-keeper 不能假设其在 PATH 中——**需先刷新/显式指定路径**。macOS 路径不同，由引导 skill（task #15）在配置期探测并写入 kb-keeper 可读的配置（如 `${DMSEEK_OBSIDIAN_CLI}` 环境变量占位）。
2. **PATH 刷新**：新装/新会话可能 PATH 未刷新；kb-keeper 调用前应能容错「命令未找到」并提示走显式路径。
3. **不可读 dot-dir（两个层面，critic C10 延伸）**：obsidian CLI **读不了以 `.` 开头的目录**。
   - **(a) vault 内部目录命名**：KB vault 目录结构（§4）**一律不使用 dot 前缀目录**（如不能用 `.queries/`，用 `queries/`）。这是目录设计的硬约束。
   - **(b) vault 根路径选址（C10）**：若 **vault 根目录本身、或其路径任一父段以 `.` 开头**（如 `~/.obsidian-vault/`、`/home/u/.kb/dm-seek/`），整个 vault 都会被 obsidian CLI 读不到，kb-keeper 直接瘫痪且报错可能不直观。⇒ **引导 skill（task #15）在探测/确认 vault 路径时须校验**：发现 vault 根或任一父段以 `.` 开头 → 提示用户「该路径 obsidian CLI 不可读，请改用非 dot 路径」。这是把本约束从「目录命名」延伸到「路径选址」，一句校验即可（归 T15 实现注意事项，见 §7 第6条）。
4. 跨平台：CLI 路径与可执行名（`.com` vs 无后缀）由引导 skill 适配；kb-keeper 经环境变量/配置取，不硬编码。

### 3.3 kb-keeper 工具白名单（呼应 design-mcp-config-shape.md §1.2）

- kb-keeper `tools`：`Bash`（调 obsidian CLI）+ `Skill`（调 Knowlery `/ask` `/cook`）+ 必要的 `Read`（读自身配置）。
- kb-keeper **不含**任何 `mcp__github-*` / `mcp__jira`（不直连代码/Jira 源）。
- 其它 agent **不含**调 obsidian CLI 的能力路径 / Knowlery 写命令（读写 KB 独占 kb-keeper）。

> **运行形态分叉对 skills 加载的影响（交叉引用 design-mcp-config-shape.md §1）**：本项目运行形态已裁决为**路径 B（agent team teammate）**。`skills` 与 `mcpServers` frontmatter **同受此分叉影响**——官方语义下，teammate **不应用** subagent 定义的 `skills`/`mcpServers` frontmatter 字段，而是从 **project/user settings（项目级 `.claude/skills/`）** 加载，同常规会话。
> ⇒ **Knowlery skill 必须放项目级 `.claude/skills/`**（不能靠 kb-keeper frontmatter `skills` 预加载）；kb-keeper 经 `Skill` 工具在运行时调用。「KB 读写独占 kb-keeper」因此也是**策略级约束（靠 kb-keeper 之外的 agent `tools` 不含 KB 写路径）、非物理隔离**——与 GitHub/Jira MCP 的独占退化同源（详见 design-mcp-config-shape.md §1.0/§1.2.1）。此点 T8 骨架与 T10/T15 实现须遵循。

---

## 4. KB 目录结构（沿用 vault 既有约定 + 本系统命名空间）

> PRD §11.2：目录结构沿用 vault 既有约定，结论写入 `queries/`。本系统在此之上加 repo 命名空间与建库分区。**所有目录无 dot 前缀**（§3.2 约束）。

```
<vault-root>/
  queries/                      # 结论沉淀区（PRD 指定）；查询结论 + 建库产出的可查条目
    <repoSlug>/                 # 按 repo 命名空间隔离（多仓）
      <query-or-topic-slug>.md  # 单条结论/主题条目（SCHEMA 见 §6）
  modules/                      # 建库期粗粒度模块条目（可选分区，亦可并入 queries/ 视 vault 约定）
    <repoSlug>/
      <module>.md
  entrypoints/                  # 建库期入口点索引（REST/Kafka 种子）
    <repoSlug>/
      rest.md / kafka.md
  _meta/                        # init 元数据（范围、时间、commit HEAD）——无 dot 前缀
    <repoSlug>.init.md
```

> 注：`modules/` `entrypoints/` `_meta/` 是否独立分区，取决于真实 vault 的既有约定——若 vault 习惯把一切结论都放 `queries/`，则建库条目也落 `queries/<repoSlug>/` 并以 SCHEMA 的 `type` 字段区分（entrypoint/module/query）。**最终以 kb-keeper owner 勘察真实 vault 既有约定为准**（§7 开放点）。

---

## 5. 知识自增长（查询期细粒度沉淀）

```
[查询主流程末端，evidence-verifier 判“充分”后]
  dongmei-ma 交付报告
       │
       ▼
  kb-keeper /cook：把本次结论按 QUERY-SCHEMA 编译进 queries/<repoSlug>/<slug>.md
       - 正文：中文（O9 默认）
       - 摘要：英文摘要段（O9：中文 + 英文摘要落库）
       - 挂出处：code(file:line)/commit/工单号（PRD 强约束，每条结论可回挂）
       - 置信度：高/中/低（来自 evidence-verifier）
  → 同类问题二次查询：先 /ask 命中既有结论 → 近乎秒答；命中则跳过重溯源
```

- **细粒度 vs 粗粒度**：建库是粗粒度骨架；查询沉淀是细粒度（具体问题的完整证据链 + 解读）。二者同落 `queries/`，靠 SCHEMA `granularity` 字段区分。
- **增量**：已存在同主题条目 → `append` 补充新证据/新时间点，而非覆盖；保留演进。

---

## 6. 沉淀 SCHEMA（可校准占位）

> 以下为 `/cook` 编译目标的字段契约占位。Knowlery 的实际 SCHEMA 机制（是否用 frontmatter、字段名）实现期校准（§7）。设计意图是「结论可回挂出处 + 中英双语 + 置信度」三要素必须落库。

```markdown
---
type: query | entrypoint | module        # 条目类别
granularity: coarse | fine               # 建库粗粒度 / 查询细粒度
degraded: false | true                    # 降级交付记录标志（C7，见下）；默认 false
repo: <repoSlug>
scope: <service/module/package 或 query 原文>
confidence: 高 | 中 | 低                  # 仅 query 类有；来自 evidence-verifier
sources:                                  # 出处回挂（PRD 强约束）
  code: ["<file>:<line>", ...]
  commits: ["<sha> DELI-xxxx", ...]
  jira: ["DELI-xxxx", ...]
created: <date>
repo_head: <commit-sha-at-init/query>     # 版本基线，供过时判定
---

# <标题（中文）>

## 当前实现状态        # 代码现实
## 演变时间线          # Git + 工单号
## 根因解释            # Jira 业务原因
## 置信度与缺口        # 高/中/低；证据不足时标注缺哪一源

---
## English Summary     # O9：英文摘要段（按需/附随，非全文翻译）
<一段英文摘要，覆盖状态/演变/根因要点>
```

- **建库期条目**（entrypoint/module，coarse）：只填到「当前实现状态（骨架）+ 关键 commit/工单线索」，`confidence` 留空，English Summary 可省（建库默认中文骨架，英文摘要在该条目首次被查询细化时补）。
- **查询期条目**（query, fine）：四段齐全 + 置信度 + 中英摘要。
- **降级交付条目**（`degraded: true`，C7 / 与 core-dev C2 联动）：返工 2 轮仍证据不足而降级交付（PRD §4.1 O5）时，结论**仍写 KB 留轻量记录**（便于追溯与后续补全），但 `degraded: true` 标记 + `confidence` 多为「低」/「中」。**`/ask` 命中 `degraded:true` 条目时不得当权威秒答**——须提示「此为证据不足的降级结论，建议重新溯源/补证」，由 kb-keeper 在 `/ask` 检索逻辑中据此字段过滤或降权（实现期 T10 落地）。语义与 core-dev 的 C2 对齐。

---

## 7. 开放点裁定（tech-lead 2026-06-12 裁定，实现期执行）

1. **Knowlery 精确接口** —— **裁定：不阻塞设计**。Knowlery 为非公开/内部插件，`/ask` 引用格式、`/cook` SCHEMA 字段作为**意图占位**，实现期（T10）对照真实插件校准。**硬契约锁定**：「出处可回挂 + 中英双语 + 置信度」三要素必须落库（字段名可调，三要素不可缺）。
2. **vault 分区** —— **裁定：并入 `queries/` 用 `type` 字段区分**（entrypoint/module/query），不独立分区，贴合既有约定。**`_meta` 同并入、且不得用 dot 前缀**（§3.2 硬约束）。真实 vault 既有约定的最终勘察留 T10/T15 实现期（kb-keeper 经 obsidian CLI 勘察后微调）。设计层据此定稿。
3. **建库调用链深度** —— **裁定：默认到 Repository/Domain 止**（调用链末端 = 存储层 / 领域对象），提供可配 `maxDepth`，防大仓链路爆炸。**此默认与 T2 规则表「调用链终点 = 存储层双形态（`db().repository` + `config(MongoConfig).collection/.view`）」对齐**（见 §2.1、§2.2）。
4. **英文摘要落库粒度** —— **裁定：建库期不产英文摘要**（粗粒度只中文）；**查询细化时**（`/cook` 写 `queries/`）才产「中文正文 + 英文摘要」。符合 O9「默认中文、英文按需/附随」。
5. **obsidian CLI 跨平台二进制（仍为实现期事项）**：Windows `D:\obsidian\Obsidian.com` 已知；macOS 路径/可执行名待引导 skill（task #15）探测；统一经 `${DMSEEK_OBSIDIAN_CLI}` 环境变量注入 kb-keeper。
6. **vault 根路径 dot 前缀校验（critic C10，归 T15 实现注意事项）**：引导 skill 探测/确认 vault 路径时，须校验 **vault 根目录或其路径任一父段是否以 `.` 开头**——若是，则该路径 obsidian CLI 不可读，提示用户改用非 dot 路径（见 §3.2 第3条(b)）。把「dot 不可读」约束从 vault 内部目录命名延伸到 vault 根选址，一句校验即可，不阻断设计。

---

## 8. 对下游任务的契约要点

- **task #10 kb-keeper 实现**：唯一读写口；obsidian CLI 四动作 + Knowlery `/ask` `/cook`；遵守 §3.2 CLI 注意事项；tools 白名单见 §3.3；SCHEMA 落库见 §6。
- **task #15 KB-init skill 实现**：实现 §2 流程（编排 code-analyst/repo-tracer/jira-tracer，写库经 kb-keeper）；支持默认全量 + scope 限定（§2.3）；多仓分别 init（§2.4）；双源来源（§2.5）；探测并注入 obsidian CLI 路径（§3.2、§7.3）。
- **依赖 task #2**：建库遍历的入口/调用链识别以 `design-core-ng-recognition.md` 为准（§2.1 已据坐实结论先行）。
- **依赖 design-mcp-config-shape.md**：repo 命名空间与映射表（§2.4）、kb-keeper 不连 MCP（§3.3）。
