# dm-seek 运行时规则（runtime-spec）

> 本文是 dm-seek（马冬梅计划）agent team 的**运行时规则单一载体**：agent / skill 在运行时引用本文对应小节。
>
> 引用约定：agent / skill 以 `runtime-spec §N` 形式引用本文小节（如 `§3 九类场景`）。

## §1 硬约束：以代码为唯一事实基准

- 一切结论必须能回挂到具体的**代码 / commit / Jira 工单**出处；无出处的判断不冒充结论。
- 当「代码现实」与「记忆 / 文档 / 工单」冲突时，**以代码为锚**给出带时间线的事实，另一方记为「记录与实现的偏差」，不和稀泥、不臆造。

仓库范围由 `.claude/repos.json` 定义（详见 §12）——每个仓库以 `repoSlug` 为唯一标识，含可选 `local`（本地路径）和必填 `remote`（owner/repo/branch）。

## §2 核心溯源流程与链路步骤（P2P 链式直传 + STATUS 监控）

### 通信拓扑

```
dongmei-ma ──kickoff──→ [+ kb-keeper] + code-analyst + synthesizer  [query_plan 广播；kb-keeper 按 kbAvailable 可选]
kb-keeper ──DATA──→ code-analyst            [kb_clue_set 异步——不阻塞，30s 超时]
code-analyst ──batch N──→ synthesizer       [分批：code_location_set + repo_timeline]
code-analyst ──batch N──→ jira-tracer        [分批：ticket_ids]
code-analyst ⇄ git-tracer                    [远端取码/远端验证请求]
jira-tracer ──batch N──→ synthesizer         [分批：jira_reasons_partial；最终：jira_reasons]
```

每个 agent 同时向 **dongmei-ma** 发 STATUS（纯文本 ≤300 字）。

### 链路步骤

1. 用户提出自然语言疑问。
2. **dongmei-ma** 解析为 `query_plan`（含 `queryId`/`round`/`depth`/`kbAvailable`），kickoff 广播。
3. **kb-keeper** 检索 KB → `kb_clue_set` 异步发 code-analyst。code-analyst 不等待——30s 内到达作线索，超时纯源码模式。
4. **code-analyst** 定位代码 → 按叙事单元分批产出（每单元：调用 git-analysis skill 提取 git 时间线 + 抽取工单号）→ 增量 batch 直达 synthesizer + jira-tracer。全部分批完成后发 `batch_complete`。
5. **git-tracer** 不产出 `repo_timeline`。仅在 code-analyst 请求时响应：远端取码 + 远端跨仓验证 + 态C 过时检测（fetch+ls-remote）。独占 GitHub MCP。
6. **jira-tracer**（normal/deep）收 `ticket_ids` 分批 → B4 缓存去重 → 分批查 Jira → `jira_reasons_partial` 直达 synthesizer → 收 `batch_complete` 后汇总发最终 `jira_reasons`。
7. **synthesizer** 渐进预处理 → 收齐 `batch_complete` + `jira_reasons` 后 B1 增量合成 → S7 evidence-check 自检 → `synthesis`（含 `selfVerification`）直达 dongmei-ma。
8. synthesizer S7 自检：sufficient → 交付+沉淀；insufficient → 附带 rework_suggestion。

### 返工协调

synthesizer 产 `rework_suggestion`；dongmei-ma 决策（分析/调度分离）。

### 增量沉淀

三源 agent 随 DATA 自行 CC `kbIncrement` 给 kb-keeper（`payloadType: "kb_increment"`，仅当 `kbAvailable=true`）；kb-keeper 按 queryId 缓存，收到 `kb_persist_request` 时与主结论同批落库。增量不经过 dongmei-ma。

### 交付输出（双层报告）

1. **高层结论（`executiveSummary`）**：面向非技术人员的业务语言摘要——将 Jira 业务原因与代码变化的高层影响编织为连贯叙事。默认不暴露类名/方法名；代码与 Jira 有出入时例外允许暴露以定位差异。
2. **完整推导（`final_report`）**：当前实现状态 + 演变时间线（含工单号）+ 根因解释（降级时为「证据不足」声明）+ 置信度（高/中/低）+（降级时）缺口标注。每条结论挂出处。

结论自动沉淀至 KB `queries/`，同类问题下次秒答；增量发现随终局沉淀 append 至 `modules/`/`entrypoints/`。

### depth 条件跳步（O10）

dongmei-ma 根据自然语言信号判定查询深度（kb-keeper 参与由 `kbAvailable` 决定，与 depth 无关）：

| depth | 数据源 | 参与 agent | 预估耗时 |
|-------|--------|-----------|:------:|
| `shallow` | code | code-analyst → synthesizer | ~1 min |
| `normal` | code + git | code-analyst → synthesizer（git-tracer 待命） | ~2 min |
| `deep` | code + git + jira | + jira-tracer | ~3 min |

**判定规则**：
- `shallow`：含"是什么""做什么""在哪里""解释一下"等信号，单个类/方法询问无历史追问
- `normal`（默认）：含"什么时候""谁改的""最近改动"等信号，涉及时间/变更但不追问业务原因
- `deep`：含"为什么""原因""Jira""业务背景"等信号，追问动机/业务上下文

**各 agent 按 depth 行为**：

| agent | shallow | normal | deep |
|-------|---------|--------|------|
| kb-keeper | 可选，异步 concept-map → kb_clue_set | 同 shallow | 同 shallow |
| code-analyst | 只产 code_location_set（不分批） | 按叙事单元分批产 code_location_set + repo_timeline + ticket_ids | + 分批 ticket_ids 直达 jira-tracer |
| git-tracer | 不参与 | 待命：code_fetch_request + 态C 过时检测 | 同 normal |
| jira-tracer | 不参与 | 收 ticket_ids → 分批查 Jira → jira_reasons_partial | 同 normal |
| synthesizer | 等 1 源（code） | 渐进收 code+git+jira → batch_complete 后合成 | 同 normal |

### 追问模式（followUpTo 非 null）

- **检测**：dongmei-ma 根据追问信号判定（"那...呢""展开""深入"等）
- **kickoff**：仅 code-analyst + synthesizer（deep 追问加 jira-tracer），不发 kb-keeper + git-tracer
- **产出**：code-analyst 基于 followUpFocus 缩小范围增量产出；synthesizer 增量合成，轻量校验
- **queryId**：新 queryId，followUpTo 指向上轮 queryId

### agent 间通信协议（标准信封，硬约束）

所有结构化产物 SendMessage 必须带标准信封：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `queryId` | string | 必填 | 全链路唯一，贯穿所有返工轮次 |
| `round` | number | 必填 | 首轮=0，发散重派+1，上限 2。仅 dongmei-ma 维护 |
| `from` | string | 必填 | 产出方 agent id |
| `to` | string | 必填 | 目标 agent id |
| `payloadType` | string | 必填 | 枚举：`query_plan`/`kb_clue_set`/`code_location_set`/`code_fetch_request`/`code_fetch_response`/`repo_timeline`/`jira_reasons`/`jira_reasons_partial`/`kb_increment`/`re_dispatch`/`synthesis`/`final_report`/`kb_persist_request`/`batch_complete` |
| `batchInfo` | object | 条件 | `{index, estimatedTotal?, isLast?, totalBatches?, narrativeName?, errors?}`。分批产出时必填 |
| `re_dispatch` | object | 条件 | `{targetAgent, hints[], round, scope?, targetBatches?}`。返工派发时必填 |
| `payload` | object | 必填 | 对应 payloadType 的具体内容 |

**产出方**：消息体以标准信封开头——显式写明 `queryId`/`from`/`to`/`payloadType`，内容放入 `payload`。纯文本消息（idle通知/报到）不在此限。

**消费方**：收到含 `payloadType` 的消息 → 按类型识别消费 `payload`，不当作普通闲聊。dongmei-ma 收到后立即消费并推进链路。

**信封透传**：除 dongmei-ma 外，其余 agent 透传 `queryId`/`round`，不改写、不自增。

## §3 九类应用场景

供 dongmei-ma 分类 `intent`/`scenario`、synthesizer 选分析方法。清单可扩展、非封闭集合。

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

### §4.1 角色职责清单（6 agent，平级 teammate）

| id | 职责 | 允许的源类 MCP |
| --- | --- | --- |
| `dongmei-ma` | 协调者：用户接口、解析疑问、调度链路、校验返工、中文交付。绝不自行补位——成员无响应走拉回流程 | **无** |
| `kb-keeper` | 唯一 Obsidian KB 读写口：concept-map 索引检索 + 结论沉淀。不读源码 | **无**（经 obsidian CLI，非 mcp） |
| `code-analyst` | 定位解读 core-ng 代码；独占本地 git（Bash 直读）；调用 git-analysis skill 统一产出 `repo_timeline` + 工单号抽取；按叙事单元分批交付；远端取码经 git-tracer | **无**（本地代码直读 + 本地 git 经 Bash；远端经 git-tracer） |
| `git-tracer` | GitHub 远端网关，**独占 GitHub MCP**（只读子集）；远端取码响应；远端跨仓验证；态C 过时检测（fetch+ls-remote）。不产出 `repo_timeline` | `mcp__github__*`（只读） |
| `jira-tracer` | 经 Atlassian Plugin 取工单业务原因与因果脉络。收 ticket_ids → 分批查 Jira → jira_reasons_partial | `mcp__atlassian__*`（只读） |
| `synthesizer` | 综合 code+git+jira → 结论（9 类场景）；分析方法沉淀为 skill | **无**（消费上游三源产物） |

> `design-tracer`（Figma 设计追溯）为二期。

### §4.2 独占 = 软边界（两防线）

teammate 形态下 MCP server 由官方 plugin 自行注册，会话层面对全 team 可见。「独占」靠两防线构成软边界：

1. **声明层**：每 agent 定义含 `职责范围`/`允许使用的 MCP 服务`/`边界约束` 三段固定区块——禁调领域外 `mcp__`，跨域需求经消息向 owner 请求。
2. **校验层**：evidence-check skill 自检时标记结论引用声明范围外工具的边界违规。

> L1 tools 白名单在 body > ~40 行时不生效（2026-06-16 qa-engineer 实证），已降级为设计意图文档。本系统「独占」= 声明层 + 校验层软边界，不依赖、不宣称物理隔离。

### §4.3 关键归属

- **GitHub MCP（远端）独占 git-tracer**；code-analyst 远端取码经 git-tracer（自身禁调 GitHub MCP）。本地 git 历史独占 code-analyst（Bash 直读 + git-analysis skill 统一收口 `repo_timeline`）。
- Obsidian KB 读写唯一收口 kb-keeper。
- dongmei-ma / synthesizer 不直连任何源。

### §4.4 只读政策

所有对代码、GitHub、Jira 的操作只读。唯一例外：
1. `git fetch`（态C 过时检测，参数最小化——`--no-auto-gc`/`--no-tags`）
2. KB 写操作（归 kb-keeper，KB 定位即知识沉淀存储）
3. 报告文件写入（synthesizer 写 `.claude/reports/` 下 `.html`/`.md`）

**严禁** `push`/`commit`/`reset`/`checkout`/`tag`/`rebase`/`stash`/`rm` 等改变仓库状态的操作。Jira 仅 get/search；GitHub MCP 仅 get/search。

### §4.5 反接管规则（硬约束）

dongmei-ma 对任何溯源链路环节不具备该领域 tools/权限/能力，绝不自行为其补位。成员无响应时执行**拉回流程**（三步升级）：SendMessage 重新拉回 → TaskList+TaskGet 确认状态 → 升级汇报用户。

**严禁**：自行接手任务、Agent spawn 替代成员、TeamCreate 新建团队绕过。详细规则见 `dongmei-ma.md` §7。

### §4.6 启动自检与就绪门控

每 agent 启动时执行领域自检（各 agent 定义 §0），向 dongmei-ma 发就绪报到（含 ✅/⚠️）。

dongmei-ma 就绪门控（30s 超时）：
- kb-keeper 超时可降级跳过（`kbAvailable=false`），后续报到时自动恢复
- 其余 4 人超时不可降级，升级汇报用户
- 就绪通知汇总各成员自检状态，⚠️ 项如实列出风险

静默规则、用户输出过滤详见 `dongmei-ma.md` §0.1~§0.2。

## §5 校验返工循环与降级（O5）

- **返工上限：最多 2 轮**。dongmei-ma 依 synthesis.selfVerification 判定驱动。
- sufficient → 交付 + 沉淀。insufficient（低/关键结论无出处）→ round<2 且有新增维度则发散重派、round+1；否则降级交付。
- **部分返工**：`rework_suggestion` 含 `scope`（`code_only`/`git_only`/`full`）和可选 `targetBatches`。返工结果以增量 batch 发送（`isRework: true`）。
- **降级交付**：照常出报告，明确声明「证据不足」+ 标注具体缺口，不无限循环、不臆造。
- **防空转**：每轮必须有新增维度；无新增维度的重派无效。

## §6 置信度三级判据（O4）

- **高**：code∧git∧jira 三源齐备且互相印证（三元闭环、无未解冲突）；每条结论挂合法出处且维度匹配；root_cause 有独立 jira 印证。
- **中**：缺 jira 业务原因，或仅 git 时间线，或 root_cause 仅由充分 commit message 顶替（**封顶中**）；结论各有出处。
- **低**：关键结论依赖推断/缺直接出处；或仅单源；或三源矛盾无法以代码定论。

附加下调因素：`shallowWarning`；漏仓；`missingTickets` 非空；大量 `noTicket`；态 C 用本地/无法比对远端；`crossRepoChainBroken`、`unmatchedDependency`。

## §7 工单号抽取（O3）

- 执行方：**code-analyst**（调用 git-analysis skill）。
- 默认正则 `^([A-Z]+-\d+)[:\s]`（冒号或空格分隔，位于 commit subject 开头；本仓 `DELI-\d+`），可配置。
- **容错无号**：无匹配 → `ticketIds=[]`、`noTicket=true`，commit 仍纳入时间线。
- **Revert 穿透**：`Revert "<原 subject>"` → 穿透引号抽号填 `ticketIds`，置 `isRevert=true`。

## §8 KB 初始化与索引（O7）

### §8.0 KB 定位：可选加速器

KB 在 dm-seek 中是**可选加速器**，不是必要链路。关闭 KB 不损失分析能力，只失去缓存加速。

**降级路径**：

| KB 状态 | concept-map 检索 | 既有结论秒答 | 结论持久化 | 增量积累 |
|---------|:---:|:---:|:---:|:---:|
| 可用（`kbAvailable=true`） | ✅ | ✅ | ✅ 写 `queries/` | ✅ 追加 `modules/`/`entrypoints/` |
| 不可用（`kbAvailable=false`） | ❌ 纯源码 Grep | ❌ | ❌ 仅存会话内存 | ❌ |

**按需启用**：KB 初始化需用户显式触发（"帮我初始化 KB"/"建立知识库"），不自动执行。

### §8.1 KB 初始化

- 可选动作、不设上限：默认初始化全部入口点，支持按需/指定范围。
- **入口点**：RESTful 接口定义 + Kafka 消费者。
- **建库方式**：沿入口类及调用链上的类的提交记录 + Jira 做粗粒度建库。多仓分别 init，KB 内按 `<repoSlug>/` 命名空间隔离。
- **知识自增长**：后续查询按需细粒度沉淀到 `queries/`，增量追加到概念索引。

### §8.2 概念索引（concept-map.md）

KB 检索主数据源——概念→代码映射表，kb-keeper 直接 Read 此文件替代 Obsidian search:context。

**路径**：`<vault-root>/index/<repoSlug>/concept-map.md`

**YAML schema**（frontmatter 为检索唯一数据源）：

```yaml
concepts:
  - id: <kebab-case>
    concept: <中文概念名>
    aliases: [string*]            # ≥3 个，覆盖中英文变体
    repo: <repoSlug>
    module: <模块名>
    entries:
      - symbol: <全限定类名>
        method: <方法名>
        file: <相对路径>
        line: <行号>
        role: entrypoint|REST-endpoint|domain|service|repository
    call_chain: [string*]
    keywords: [string*]
    jira:
      - key: <工单号>
        summary: <工单标题>
        business_reason: <业务原因摘要>
        fetched: <ISO 8601>
    confidence: high|medium|low
    created: <date>
    updated: <date>
```

**检索策略**：kb-keeper Read → 解析 YAML → 分词逐条匹配 `aliases`（+3）/ `keywords`（+1）/ `concept` 名（+5）→ Top 5 → 组装 `kb_clue_set`。最高分 < 2 → 回退 code-analyst 源码 grep。

**构建与增量**：KB-init 阶段 code-analyst 遍历入口/调用链自动提取 → kb-keeper 写入。查询完成后，新概念映射通过 `kbIncrement`（`kind=concept_mapping`）CC kb-keeper → 收到 `kb_persist_request` 时统一追加到 `concepts[]`。

## §9 双源切换与过时判定（O2）

仓库范围由 `repos.json`（§12）作为权威配置来源。过时判定按「被检索到的相关代码」粒度，绝不整仓比较：

| 本地仓库状态 | 行为 |
| --- | --- |
| 无本地仓库 | 全程 GitHub MCP（远端模式），code-analyst 经 git-tracer 取代码 |
| 有本地仓库，相关代码不过时（态B） | code-analyst 直读本地代码 + 本地 git + git-analysis skill 产出 `repo_timeline`。本地 git 不经 GitHub MCP |
| 有本地仓库，相关代码远端更新 | 就该段代码询问用户（dongmei-ma 唯一询问者，合并询问） |

多仓按每个涉及仓库分别判定。

## §10 core-ng 识别约定（双重落地）

- **双重落地**：依据官方约定（core-ng wiki/源码惯例）作补充印证，同时结合目标仓库实际标志——不一致时以目标仓库实际代码为准。
- 识别规则集中维护于 `.claude/skills/coreng-recognition/SKILL.md`，扩展到其他框架只新增规则段 + `coreNgRole` 枚举，不散落各 agent。

## §11 输出语言（O9）

默认中文——dongmei-ma 默认中文交付报告；英文版按需附随（用户显式请求时）。KB 沉淀采「中文 + 英文摘要」。

## §12 仓库范围配置（`.claude/repos.json`）

`.claude/repos.json` 是 dm-seek 仓库范围的权威配置文件。

### 结构

```jsonc
{
  "repos": {
    "<repoSlug>": {
      "local": { "path": "<绝对路径>" },
      "remote": { "owner": "<org>", "repo": "<name>", "branch": "<branch>" },
      "kb": { "vault": "<Obsidian vault 名>", "path": "<相对路径>" }
    }
  },
  "enable": true,
  "manualEdges": [{ "fromRepo": "<消费方>", "toRepo": "<导出方>", "viaArtifact": "<artifactId>", "reason": "<原因>" }]
}
```

- `local`：可选，本地仓库绝对路径。纯远端仓库省略
- `remote`：必填，owner/repo/分支
- `kb`：可选，KB vault 配置。初始化脚本自动写入。无此字段表示 KB 未初始化
- `enable`：可选，默认 `true`。`false` 时脚本/agent 跳过此仓库
- `manualEdges`：可选，手动声明的跨仓边，与自动推断 edges 对等，dependency-graph.json 中合并去重（source=manual|auto）
- **分支一致性**：同时存在 local 和 remote 时，远端操作使用本地当前分支一致的远端分支

### agent 使用职责

| agent | 读取 | 用途 |
|-------|------|------|
| git-tracer | `remote.owner`/`repo` | GitHub MCP 参数 |
| code-analyst | `local.path` + `remote` | 态B 直读 + 本地 git；多仓路由 |
| dongmei-ma | 全量（含 `enable`、`manualEdges`） | 仓库感知、过时询问、跨仓展示 |
| setup 脚本 | `enable` | Phase 8 遍历 enable=true 仓库 |

setup-guide 负责引导用户写入。code-analyst 在 `round` 变更时重新读取反映手动更新。

---

## §13 跨仓依赖图（`.claude/dependency-graph.json`）

由 setup 脚本 Phase 8 自动生成。**不提交 git**，已加入 `.gitignore`。

### 结构与字段

```jsonc
{
  "schemaVersion": "1.0",
  "generatedAt": "2026-06-24T10:00:00Z",     // ISO 8601，过时检测用
  "enabledRepos": ["hdr-delivery-project", "hdr-project"],
  "repoHeadShas": { "hdr-delivery-project": "abc123..." },  // SHA 增量缓存
  "edges": [{                               // 跨仓依赖边
    "fromRepo": "hdr-delivery-project",
    "toRepo": "hdr-project",
    "viaArtifact": "kitchen-management-service-interface",
    "versionConsumed": "28.2.0",
    "versionExported": "28.2.1",
    "versionMatch": "behind",               // exact|behind|ahead
    "relationship": "api-contract",
    "source": "auto"                        // auto|manual
  }],
  "reverseEdges": { "hdr-project": [{"fromRepo": "...", "viaArtifact": "..."}] },
  "unmatched": [{
    "repo": "hdr-delivery-project",
    "artifact": "com.wonder:order-service-interface:130.1.11",
    "likelyMissingRepo": "order-service",
    "likelyThirdParty": false
  }],
  "cyclesDetected": false
}
```

### 生成触发

| 方式 | 说明 |
|------|------|
| 初始化脚本 [8] | setup 菜单 `[8] 刷新依赖图` |
| 自动扫描 | 启动时自动执行（SHA 未变则复用缓存） |

### agent 读取职责

| agent | 读取字段 | 用途 |
|-------|---------|------|
| dongmei-ma | `edges`、`unmatched`、`reverseEdges` | 跨仓关系展示 |
| code-analyst | `edges` | reposInvolved 填充 viaArtifact + commit 验证 → crossRepoEvidence |
| git-tracer | `edges` | 远端跨仓验证协助（无本地 clone 时） |
| synthesizer | `edges` | cross-repo-causal-v1 输入 |
| kb-keeper | `edges` | 跨仓扫描预填充 concept-map / shared/cross-repo-index |

### 文件不存在或损坏时

agent 必须 try/catch 包裹 Read。缺失/解析失败 → 静默跳过，不阻塞查询、不报错。

### 过时检测

`generatedAt` 与仓库最新 HEAD 对比——启用仓库当前 HEAD 晚于 generatedAt 则标记"可能过时"，提示用户运行 setup [8] 刷新。agent 不自动重新生成。
