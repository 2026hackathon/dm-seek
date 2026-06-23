# dm-seek 运行时规则（runtime-spec）

> 本文是 dm-seek（马冬梅计划）agent team 的**运行时规则单一载体**：agent / skill 在运行时引用本文对应小节。
>
> 引用约定：agent / skill 以 `runtime-spec §N` 形式引用本文小节（如 `§3 九类场景`）。

## §1 硬约束：以代码为唯一事实基准

核心原则 **code as the single source of truth**：

- 一切结论必须能回挂到具体的**代码 / commit / Jira 工单**出处；无出处的判断不冒充结论。
- 当「代码现实」与「某人的记忆 / 文档描述 / 工单」冲突时，**以代码为锚**给出带时间线的事实，把另一方记为「记录与实现的偏差」，不和稀泥、不臆造。

### 仓库范围

dm-seek 分析的仓库范围由 `.claude/repos.json` 定义——每个仓库以 `repoSlug` 为唯一标识，含可选的 `local`（本地路径）和必填的 `remote`（owner/repo/branch）。同时存在 local 和 remote 时，远端操作使用与本地当前分支一致的远端分支。全链路 agent（code-analyst/repo-tracer）以此文件为仓库路由权威来源。结构与职责详见 §12。

## §2 核心溯源流程与链路步骤（P2P 链式直传 + STATUS 监控）

### 通信拓扑

```
dongmei-ma ──kickoff──→ kb-keeper + code-analyst + synthesizer [query_plan 广播]
kb-keeper ──DATA──→ code-analyst            [kb_clue_set 直达]
code-analyst ──DATA──→ repo-tracer + synthesizer [+ jira-tracer]  [按 depth]
repo-tracer ──DATA──→ jira-tracer + synthesizer  [直达]
jira-tracer ──DATA──→ synthesizer           [只发一次]
synthesizer ──DATA──→ evidence-verifier     [synthesis 直达]
evidence-verifier ──DATA──→ dongmei-ma + synthesizer  [verification 双向]
```

每个 agent 同时向 **dongmei-ma** 发 STATUS（纯文本 ≤300 字）供进度监控。

### 链路步骤

1. 用户提出自然语言疑问。
2. **dongmei-ma** 解析为 `query_plan`（含 `queryId`/`round`/`depth`），kickoff 广播给 kb-keeper + code-analyst + synthesizer。
3. **kb-keeper** 检索 KB → `kb_clue_set` 直达 code-analyst + STATUS 给 main。
4. **code-analyst** 等 qp+kb_clue 齐备 → 定位代码 → 按 depth 直达下游 + STATUS 给 main。
5. **repo-tracer**（normal/deep）直收 → `repo_timeline` 直达 synthesizer + `ticket_ids_all` 直达 jira-tracer（deep）+ STATUS。B5：信任 localGitTimeline。
6. **jira-tracer**（deep）双源去重 → B4 缓存 → `jira_reasons` 直达 synthesizer（只发一次）+ STATUS。
7. **synthesizer** expectedSources 收齐 → B1 增量合成 → `synthesis` 直达 evidence-verifier + STATUS。
8. **evidence-verifier** 校验 → `verification` 双向发 dongmei-ma + synthesizer。sufficient → 交付+沉淀；insufficient → synthesizer 出 `rework_suggestion`，dongmei-ma 返工终局决策。

### 返工协调

synthesizer 产 `rework_suggestion`；dongmei-ma 决策（分析/调度分离）。

### 增量沉淀

三源 agent 随 DATA 上报 `kbIncrement`；终局归并入 `kb_persist_request`。

### 交付输出（双层报告）

1. **高层结论（`executiveSummary`）**：面向非技术人员（产品经理/测试）的自然语言结论摘要——用纯业务语言将 Jira 业务原因与代码变化的高层影响编织为连贯叙事。默认不暴露类名/方法名/字段名等代码标识；代码与 Jira 有出入时例外允许暴露以定位差异。以一段简述式结尾收官。帮助读者快速理解核心结论，再决定是否查阅完整推导。
2. **完整推导（`final_report`）**：当前实现状态（代码现实）+ 演变时间线（含工单号）+ 根因解释（Jira 业务原因；降级时为「证据不足」声明）+ 置信度（高 / 中 / 低）+（降级时）缺口标注。每条结论挂出处（code/commit/jira）。

结论自动沉淀至 KB `queries/`，同类问题下次秒答；多 agent 增量发现随终局沉淀 append 至 `modules/`/`entrypoints/`。

### depth 条件跳步（O10）

dongmei-ma 根据用户问题中的自然语言信号自动判定查询深度，跳过不必要的 agent：

| depth | 需要数据源 | 参与 agent | 预估耗时 |
|-------|-----------|-----------|:------:|
| `shallow` | code | kb-keeper → code-analyst → synthesizer → evidence-verifier | ~1 min |
| `normal` | code + git | + repo-tracer | ~2 min |
| `deep` | code + git + jira | + jira-tracer | ~3 min |

**判定规则**（由 dongmei-ma 在解析 query_plan 时执行）：

```
含以下信号 → shallow:
  "是什么" "做什么" "怎么用" "在哪里" "解释一下" "看一下"
  单个类/方法询问，无历史/原因追问

含以下信号 → normal:
  "什么时候" "谁改的" "哪个版本" "最近改动" "提交记录"
  涉及时间/变更，但不追问业务原因

含以下信号 → deep:
  "为什么" "原因" "需求" "工单" "Jira" "业务背景" "谁要求的"
  追问动机/业务上下文

默认 depth: normal（宁可多跑一个 git，不漏信息）
```

**各 agent 按 depth 的行为**：

| agent | shallow | normal | deep |
|-------|---------|--------|------|
| code-analyst | 只产出 code_location_set | + 产出 localGitTimeline | + 抽取 early_ticket_ids |
| repo-tracer | 不参与 | 产出 repo_timeline | + 抽取 ticket_ids_all |
| jira-tracer | 不参与 | 不参与 | 收双源 → 查询 Jira |
| synthesizer | 等 1 源（code） | 等 2 源（code+git） | 等 3 源（code+git+jira） |
| evidence-verifier | 轻量校验（code 出处 + 置信度） | 正常校验 | 完整校验（含边界违规） |

### agent 间通信协议（标准信封，硬约束）

**所有 agent 间经由 SendMessage 发送的结构化产物，必须带标准信封。** 信封定义如下：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `queryId` | string | 必填 | dongmei-ma 生成，全链路唯一，贯穿所有返工轮次 |
| `round` | number | 必填 | 返工轮次。首轮=0，发散重派+1，上限 2。仅 dongmei-ma 维护 |
| `from` | string | 必填 | 产出方 agent id（见 §4.1 角色 id） |
| `to` | string | 必填 | 目标 agent id |
| `payloadType` | string | 必填 | 载荷类型枚举：`query_plan` / `kb_clue_set` / `code_location_set` / `code_fetch_request` / `code_fetch_response` / `repo_timeline` / `jira_reasons` / `synthesis` / `verification` / `final_report` / `kb_persist_request` |
| `payload` | object | 必填 | 对应 payloadType 的具体内容（结构化描述，不强制 JSON 代码块，但字段须无歧义可提取） |
| `chunkInfo` | object | **已废弃** | 1M 上下文窗口下不再需要分片，此字段始终省略 |

**产出方（硬性）**：发送结构化产物时，消息体必须以标准信封开头——显式写明 `queryId`、`from`、`to`、`payloadType`，然后将具体内容放入 `payload`。不使用信封的纯文本消息（如 idle 通知、报到消息）不在此限，但**凡包含下游需消费的结构化数据，必须用信封**。

**消费方（硬性）**：收到 teammate 消息时，先检查是否含 `payloadType` 字段——若有，按类型识别并消费 `payload`；不要将结构化产物当作普通闲聊来回应。dongmei-ma 收到带 `payloadType` 的消息后**立即消费并推进链路**，不等待、不向产出方索要自然语言描述确认。

**信封透传**：除 dongmei-ma 外，其余 agent 收到上一环产物时，透传 `queryId` / `round`，**不改写、不自增**。

### 分片通信规则（已删除）

DeepSeek V4 Pro 提供 1M 上下文窗口，全链路中间产物（code_location_set、repo_timeline、jira_reasons）总计远在窗口容量之内。**不再需要分片发送和归并**——每条 payload 以完整形式在单条消息中传递，接收方直接消费。`chunkInfo` 字段已从信封中移除，分片归并逻辑已从 dongmei-ma 和各 agent 中删除。

## §3 九类应用场景

供 dongmei-ma 分类 `intent`/`scenario`、synthesizer 选分析方法。清单**可扩展、非封闭集合**。

| # | 场景 | intent slug | 价值 |
| --- | --- | --- | --- |
| 1 | 实现与需求文档差异核查 | `change_reason` | 定位「Jira 先变还是代码先变」+ 差异时间节点与责任工单 |
| 2 | 新需求影响范围评估 | `impact_scope` | 模块依赖与历史变更模式，识别隐性耦合 |
| 3 | 缺陷责任定位 | `defect_locate` | 追溯最后修改 commit 与工单，带时间线/负责人的证据链 |
| 4 | 新成员知识加速 | `onboarding` | 三源重建模块设计决策历程 |
| 5 | 技术债务定性 | `tech_debt` | 区分「有业务原因的历史决策」与「未清理临时方案」 |
| 6 | 回归缺陷溯源 | `regression_trace` | 定位逻辑最近被触碰 commit 与工单，主动修改 vs 隐藏缺陷 |
| 7 | 功能蒸发追踪 | `feature_evaporation` | 还原功能被删除的 commit、工单与删除前最后修改 |
| 8 | 跨团队接口争议仲裁 | `interface_dispute` | 并排「约定变更记录 vs 代码实现记录」 |
| 9 | 设计与实现对齐审查（含 Figma） | （二期） | 并排「代码改了什么」与「设计意图」，**二期能力** |

## §4 角色职责与独占机制（软边界 / 两防线）

### §4.1 角色职责清单（首版 7 agent，平级 teammate）

| id | 职责 | 允许的源类 MCP |
| --- | --- | --- |
| `dongmei-ma` | 协调者 teammate（类似 tech-lead）：用户接口、解析疑问、拆解派发任务、消息驱动校验返工循环、默认产出中文报告交付；非他人之父、不委派独占下游。**绝不自行为任何 teammate 补位**——成员无响应时走拉回流程（§4.5），不接手任务、不 spawn 替代者 | **无**（不直连任何信息源） |
| `kb-keeper` | 边界唯一 Obsidian KB 读写口：给线索 + 结论沉淀回写；不读源码。集成 = obsidian CLI（search/read/create/append）+ `concept-map.md` 索引检索 | **无 `mcp__`**（KB 经 obsidian CLI 读写，非 mcp） |
| `code-analyst` | 据 KB 线索定位并解读 core-ng 代码；KB 未命中源码兜底；KB 初始化时遍历入口/调用链；定位映射到具体 repo+模块；态B 经 Bash 直读本地 git 历史作本地 git 证据 | **无 `mcp__`**（本地代码直读 + 本地 git 经 Bash；远端取码/远端历史经 repo-tracer，绝不自连 GitHub MCP） |
| `repo-tracer` | Git/GitHub 网关，**边界独占 GitHub MCP（server `github`，`官方 GitHub MCP`）**；远端取码+远端提交历史；统一收口产出提交时间线 `repo_timeline` + 抽工单号；态B 本地 git 信任 code-analyst 提供片段、未附则自取兜底 | `mcp__github__*`（`官方 GitHub MCP`，只读子集）+ 本地 git（经 Bash，**与 code-analyst 共享、非独占**） |
| `jira-tracer` | 经 Atlassian 官方 Plugin（server `atlassian`）取工单业务原因与多工单因果脉络 | `mcp__atlassian__*`（官方 Atlassian plugin，只读子集，仅 Jira get/search） |
| `synthesizer` | 综合 code+git+jira → 结论（9 类场景）；分析方法沉淀为可复用 skill | **无**（仅消费上游三源产物） |
| `evidence-verifier` | 校验每条结论是否挂出处 + 输出置信度 + 边界违规校验 + 不足触发发散返工 | **无**（仅消费上游全部产物） |

> `design-tracer`（Figma 设计追溯）为二期。

### §4.2 独占 = 软边界（两防线）

teammate 形态下 MCP server 由**官方 Claude Code plugin 自行注册**（server `github` / `atlassian`），不落 `.mcp.json`，**会话层面对全 team 可见**；「独占」靠以下两防线构成软边界：

1. **声明层（每 agent 固定区块，主防线之一）**：每个 agent 定义含三段固定区块——`## 职责范围` / `## 允许使用的 MCP 服务` / `## 边界约束`（硬性：禁调领域外 `mcp__`，跨域需求经任务列表 / 消息向 owner agent 请求，绝不直连）。
2. **校验层（evidence-verifier 运行期兜底，主防线之二）**：校验结论时标记「结论引用了声明范围外工具 / 数据来源」的边界违规。

**L1 tools 白名单已降级为设计意图文档**：各 agent frontmatter `tools` 白名单仍声明本域工具（repo-tracer 含 `mcp__github__*`；jira-tracer 含 `mcp__atlassian__*`；其余 agent 不含源类 `mcp__`），但**在 agent body > ~40 行时不生效**（2026-06-16 qa-engineer 用 CLI 2.1.177 实证，dm-seek 全部 7 agent body 均超此阈值）。白名单作为设计意图与声明层一致性校验参照，**不对引擎强制执行抱有依赖**。`deniedMcpServers` 是组织/会话级一刀切、无 per-agent 粒度、会误伤，故不采用。

> **诚实声明**：本系统「独占」= **每 agent 边界声明（声明层）+ evidence-verifier 校验（校验层）**，构成软边界。L1 tools 白名单在 body > ~40 行时不生效——不得依赖、不得宣称「物理隔离 / L1 生效 / 三道防线」。

### §4.3 关键归属

- **GitHub MCP（远端）独占 repo-tracer**；远端模式下 code-analyst 经 repo-tracer 取码与取远端历史（自身禁调 GitHub MCP）。**本地 git 历史读取权 code-analyst/repo-tracer 共享**（态B 经 Bash 直读本地仓）：code-analyst 取到的本地 git 片段经 `code_location_set.localGitTimeline` 附给 repo-tracer，repo-tracer 信任采用、统一收口产出 `repo_timeline`（抽工单号仍归 repo-tracer）。独占只针对远端 GitHub MCP。
- Obsidian KB 读写唯一收口 kb-keeper。
- dongmei-ma / synthesizer / evidence-verifier 不直连任何源。

### §4.4 只读政策

**所有对代码、GitHub 仓库、Jira 的操作都是只读的。** 除以下两项外，禁止任何写操作：

1. **`git fetch`**：拉取远端更新本地仓库（唯一允许的 git 写操作），用于过时判定（§9 态C）。
2. **KB 写操作**：归 kb-keeper，不受此限（KB 自身定位就是知识沉淀存储）。

具体约束：
- **代码文件**：所有 agent 对代码文件只读（Read/Grep/Glob），不修改、不创建、不删除任何代码文件。
- **Git 仓库**：仅允许只读操作（`log`/`diff`/`show`/`cat-file`/`fetch`/`ls-remote`），**严禁** `push`/`commit`/`reset`/`checkout`/`tag`/`rebase`/`stash`/`rm` 等任何改变仓库状态的操作。`fetch` 是唯一例外，通过 `--no-auto-gc`/`--no-tags` 等参数最小化副作用。
- **Jira**：仅允许 `mcp__atlassian__*`（官方 Atlassian plugin，只读子集——仅 Jira get/search 工具，不授予 create/update/transition/comment 写工具），杜绝任何写/修改工单的操作。
- **GitHub MCP**：远端 GitHub MCP 调用仅用于取码 + 取提交历史（只读），禁止通过 MCP 创建/修改 PR、issue、comment 等。仅允许 `mcp__github__*`（`官方 GitHub MCP`，只读子集——仅取码+历史的 get/search 工具，不授予 create/commit/delete 写工具）。

### §4.5 dongmei-ma 反接管规则（硬约束）

**协调者不是替补。** dongmei-ma 对任何溯源链路环节（kb-keeper / code-analyst / repo-tracer / jira-tracer / synthesizer / evidence-verifier）均不具备该领域的 tools/权限/能力，绝不自行为其补位。

当某 teammate 在预期时间内未响应时，执行**拉回流程**（三步升级）：

1. **SendMessage 重新拉回**：告知当前进度和等待的具体产出，把成员带回工作。
2. **TaskList + TaskGet 确认状态**：检查是否卡在 blockedBy 或依赖上。
3. **升级汇报用户**：拉不回时向用户汇报，让用户决策（检查存活 / 重启会话）。

**严禁项**：
- ❌ 自行接手该成员的任务（产出无出处、破坏分工边界）
- ❌ 用 Agent spawn 替代成员（Agent 仅启动时一次性使用；运行期 spawn = 制造重复/幽灵成员、破坏团队拓扑）
- ❌ 用 TeamCreate 新建团队绕过

### §4.6 启动自检与就绪门控

**每个 agent 启动时必须执行领域自检**（各 agent 定义 §0「启动自检」），检查本领域 tools/MCP 是否就绪，然后向 dongmei-ma 发送就绪报到（含自检结果 ✅/⚠️ + 失败项）。

**dongmei-ma 就绪门控**：
- 必须等待**全部 6 个成员**各自发来就绪报到消息后，才向用户输出就绪通知。
- 未收齐 6 人报到前，绝不输出就绪通知。
- 就绪通知须汇总各成员自检状态，⚠️ 项如实列出风险让用户知情。

**静默规则**：
- dongmei-ma 在无任务时（用户未输入查询、上一个查询已完成）**不输出任何内容**。
- 唯一输出时机：就绪门控通过 / 用户输入查询 / §4.5 拉回升级 / §9 过时询问。
- 不得周期性状态汇报、"等待中"类消息、自言自语。

**用户输出过滤**：
- dongmei-ma 是用户唯一接口，**默认屏蔽成员间原始消息**，只向用户展示进度摘要（当前环节 + 完成时一句话结果）+ 最终报告。
- 内部流量不穿透：成员的 idle 通知、报到消息、原始 JSON/结构体等不直接暴露给用户。
- 用户明确询问详情时，用自然语言概括关键信息，不贴原始 JSON 全文。
- dongmei-ma 是用户与团队之间的**信息滤波器**：内部流量不穿透，进度感知不缺失，细节按需提供。

> 详细规则见 `dongmei-ma.md` §7。

## §5 校验返工循环与降级（O5）

- **返工上限：最多 2 轮发散返工**。由 dongmei-ma 依 evidence-verifier 判定驱动（经共享任务列表 + 消息，非父子委派）。
- 充分（verdict=sufficient，高/中）→ 交付 + 沉淀。不足（insufficient，低/关键结论无出处）→ round<2 且能选出「有新增维度」的有效 hint 则发散重派、round+1；否则降级交付。
- **降级交付**：照常出报告，但明确声明「证据不足」+ 标注具体缺口（缺哪一源/哪一环），不无限循环、不臆造。
- **防空转**：每轮发散必须有相对上一轮的新增维度；无新增维度的重派 = 无效返工，不计入 round。

## §6 置信度三级判据（O4）

- **高**：code∧git∧jira 三源齐备且互相印证（三元闭环、无未解冲突）；每条结论挂合法出处且维度匹配；root_cause 有独立 jira 印证。
- **中**：缺 jira 业务原因，或仅 git 时间线，或 root_cause 仅由充分 commit message 顶替独立 jira（**封顶中**）；结论仍各有出处。
- **低**：关键结论主要依赖推断/缺直接出处；或仅单源；或三源矛盾无法以代码定论。

附加下调因素（命中则下调或标注）：`shallowWarning`；漏仓（reposCovered ⊊ reposInvolved）；`missingTickets` 非空；大量 `noTicket`；态 C 用本地 / 无法比对远端。

## §7 工单号抽取（O3）

- 默认正则 `^([A-Z]+-\d+)[:\s]`（**冒号或空格**分隔，位于 commit subject 开头；本仓 `DELI-\d+`），**可配置**（支持多项目键）。
- **容错无号**：无匹配 → `ticketIds=[]`、`noTicket=true`，不报错，commit 仍纳入时间线（置信度降级依据）。
- **Revert 穿透**：`Revert "<原 subject>"` → 穿透引号对内层再抽号填 `ticketIds`，置 `isRevert=true`（支撑场景 7 功能蒸发）。

## §8 KB 初始化与索引（O7）

### §8.1 KB 初始化

- **可选动作、不设上限**：默认初始化全部入口点，支持按需 / 指定范围初始化（某服务 / 某模块）。
- **入口点**：RESTful 接口定义 + Kafka 消费者。
- **建库方式**：沿入口类及其调用链路上的类的提交记录 + Jira 做**粗粒度**建库。多仓分别 init，KB 内按 `<repoSlug>/` 命名空间隔离。
- **知识自增长**：后续查询按需细粒度沉淀（结论写回 `queries/`），并增量追加到概念索引。

### §8.2 概念索引（concept-map.md）

KB 检索的主数据源是 `index/<repoSlug>/concept-map.md`——一份**概念→代码映射表**，kb-keeper 直接 Read 此文件进行检索，替代 Obsidian search:context。

**文件路径**：`<vault-root>/index/<repoSlug>/concept-map.md`

**YAML schema**（frontmatter 为检索唯一数据源）：

```yaml
concepts:
  - id: <kebab-case>              # 稳定标识
    concept: <中文概念名>           # 主名称
    aliases: [string*]            # NL 别名（≥3 个，覆盖中英文变体）
    repo: <repoSlug>
    module: <模块名>
    entries:                      # 代码符号精确列表
      - symbol: <全限定类名>
        method: <方法名>
        file: <相对路径>
        line: <行号>
        role: entrypoint|REST-endpoint|domain|service|repository
    call_chain: [string*]         # 调用链（符号级）
    keywords: [string*]           # 代码侧符号名（不做翻译）
    jira:                          # 关联工单缓存（B4 Jira 缓存）
      - key: <工单号>              # 如 DELI-4475
        summary: <工单标题>
        business_reason: <业务原因摘要>
        fetched: <ISO 8601>         # 首次拉取时间，用于过期检查
    confidence: high|medium|low
    created: <date>
    updated: <date>
```

**检索策略**：kb-keeper Read 此文件 → 解析 YAML → 对用户问题的分词逐条匹配 `aliases`（模糊，+3）/ `keywords`（精确，+1）/ `concept` 名（+5）→ 取 Top 5 得分 concept → 组装 `kb_clue_set`（含 `symbol`/`file`/`line`/`call_chain`）。最高分 < 2 判定未命中，回退 code-analyst 源码 grep。

**构建与增量**：
- KB-init 阶段：code-analyst 遍历入口/调用链 → 自动提取 aliases（来源：JavaDoc/commit/Jira summary/类名方法名拆词/调用链下游类名）和 keywords → kb-keeper 写入 `concept-map.md`
- 查询完成后：code-analyst/synthesizer 发现新概念映射时，通过 `kbIncrement`（`kind=concept_mapping`）上报 → kb-keeper 终局追加到 `concepts[]`

## §9 双源切换与过时判定（O2）

仓库范围由 **`repos.json`（`.claude/repos.json`）** 作为权威配置来源（§12），agent 启动时从中读取已注册仓库列表。

**过时判定按「被检索到的相关代码」粒度，绝不整仓比较**：

| 本地仓库状态（针对被检索到的相关代码） | 行为 |
| --- | --- |
| 无本地仓库（`localPath` 为空或仓库未在 `repos.json` 注册） | 全程 GitHub MCP（远端模式），code-analyst 经 repo-tracer 取代码 |
| 有本地仓库，相关代码段不过时（态B） | 使用本地仓库：code-analyst 直读本地代码内容 + 经 Bash 直读本地 git 历史（作本地 git 证据，随 `localGitTimeline` 附给 repo-tracer 收口；repo-tracer 未收到则自取兜底）。本地 git 不经 GitHub MCP |
| 有本地仓库，相关代码段远端版本更新 | **就该段代码询问用户**是否取最新（非整仓比较；dongmei-ma 唯一询问者，合并询问） |

多仓场景按每个涉及的仓库分别判定，仓库识别以 `repos.json`（§12）注册列表为准；repo-tracer 据 code-analyst 的 repo+模块映射路由到对应本地仓库或 GitHub MCP 实例。

## §10 core-ng 识别约定（双重落地）

- **双重落地**：既依据**官方约定**（core-ng wiki / 源码惯例）作补充印证，又结合**目标仓库的实际标志**——当两者不一致时，**以目标仓库实际代码为准**，不空想惯例。
- 识别规则**集中一处**维护（载体 = `.claude/skills/coreng-recognition/SKILL.md`），便于扩展到其他框架（只新增规则段 + `coreNgRole` 枚举，不散落各 agent）。
- 详细识别规则见 `skills/coreng-recognition/SKILL.md`。

## §11 输出语言（O9）

**默认中文**——dongmei-ma 默认以中文交付报告；英文版按需 / 附随提供（用户显式请求时）。KB 沉淀采「中文 + 英文摘要」。

## §12 仓库范围配置（`.claude/repos.json`）

`.claude/repos.json` 是 dm-seek 仓库范围的权威配置文件。每个仓库以 `repoSlug` 为唯一标识。

### 结构

```jsonc
{
  "repos": {
    "<repoSlug>": {
      "local": { "path": "<绝对路径>" },
      "remote": { "owner": "<org>", "repo": "<name>", "branch": "<branch>" },
      "kb": { "vault": "<Obsidian vault 名>", "path": "<相对路径>" }
    }
  }
}
```

- `local`：可选，本地仓库绝对路径。纯远端仓库省略
- `remote`：必填，GitHub 仓库的 owner、repo、默认分支
- `kb`：可选，KB vault 配置。`vault` = Obsidian vault 名（用于 obsidian CLI `vault=<name>` 参数），`path` = vault 相对于 dm-seek 项目根的路径。由 windows-setup.ps1 Phase 4 自动写入。无此字段表示该 repo 的 KB 未初始化
- **分支一致性**：同时存在 local 和 remote 时，远端操作使用与本地当前分支一致的远端分支（`git branch --show-current`）

### agent 使用职责

| agent | 读取 | 用途 |
|-------|------|------|
| repo-tracer | `remote.owner` / `repo` | GitHub MCP 工具参数 |
| repo-tracer | `local.path` | `git -C` 取本地分支、本地 git 历史 |
| code-analyst | `local.path` | 态B 直读本地代码 |
| dongmei-ma | 全量 | 仓库范围感知、过时询问 |

setup-guide（`.claude/skills/setup-guide/SKILL.md` §5）负责引导用户写入。repo-tracer 在 `round` 变更时重新读取以反映手动更新。
