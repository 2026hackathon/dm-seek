> **详细 schema 参考手册**：本文含完整 JSON 示例与字段表（§2-§7）。运行时轻量版（仅 §0 原则 + §1 信封 + §8 归属表）见同目录 `design-agent-io-schema.md`，agent 引用轻量版即可。
>
# 马冬梅计划 — Agent 间 I/O 契约与编排设计

7 agent 平级 teammate，dongmei-ma 协调者经任务列表+消息驱动。

> 本文是后续所有实现任务的**总契约**。所有 agent 的 prompt / skill 实现必须遵守此处定义的输入输出结构与编排语义。

---

## 0. 约定与说明

### 0.1 schema 表达形式

- agent 之间是 agent team teammate 间经任务列表 + 消息的自然语言协作。本文用 **JSON 形态描述「结构化载荷」**，作为各 agent 输出消息中应当包含的字段约定。
- **传递形态**：采「**自然语言为主 + 结构化字段可无歧义提取**」——agent 在自然语言回复中**必须能无歧义地给出本 schema 约定的每个字段值**，但**不强制贴 JSON 代码块**。
- 字段标注：`必填` / `可选`。类型用 `string` / `number` / `boolean` / `enum` / `array` / `object` 表示。
- 所有载荷都带一个公共信封（§1），便于在返工循环中关联同一次查询的多轮产物。

### 0.2 核心原则

- **代码为唯一事实基准**：每条结论必须可回挂到 `代码 / commit / 工单` 出处。任何 agent 产出结论性字段时，必须同时产出对应的 `evidence` 出处数组（§2.5）。
- **归属约束在契约层显式化**，见 §8。
- **离散三级置信度**（高/中/低）、**≤2 轮发散返工 + 降级交付**在编排契约（§7）中固化。

---

## 1. 公共信封（Envelope）

所有 agent 间结构化载荷共享以下信封字段，使一次查询的多轮、多 agent 产物可被 dongmei-ma 关联与归并。

> **teammate 形态下的信封语义**：7 个 agent 为**平级 teammate**，经**共享任务列表 + 消息（SendMessage）**协作；**dongmei-ma 是协调者 teammate**（非父节点、非 subagent 委派者）。信封字段在此形态下的归属：
> - `queryId`：由 **dongmei-ma 在接收用户疑问时生成**，其余 teammate 在回复消息/子任务中**透传、不改写**。
> - `round`：由 **dongmei-ma（协调者）统一维护**——每发起一轮有效发散（§7.3 有新增维度）时 +1；其余 teammate 收到带 round 的消息后**透传**，不自增。
> - `from`/`to`：标识消息的产出方与目标 teammate；「下游」指协作链路下一环，经消息/子任务流转，而非父子调用返回。
> 即：schema 与字段语义不变，仅**驱动方式为「teammate 间任务/消息协调」**。下文 §7 编排循环的「重派」一律按此理解。

```json
{
  "queryId": "q-20260612-001",
  "round": 0,
  "from": "kb-keeper",
  "to": "dongmei-ma",
  "payloadType": "kb_clue_set",
  "payload": { }
}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `queryId` | string | 必填 | 一次用户查询的唯一 id，贯穿全链路与所有返工轮次 |
| `round` | number | 必填 | 返工轮次。首轮=0；每次发散重派 +1；上限 2（即最大 round=2，见 §7） |
| `from` | enum(agent id) | 必填 | 产出方 agent id |
| `to` | enum(agent id) | 必填 | 目标 agent id（通常为 dongmei-ma 或下游 agent） |
| `payloadType` | enum | 必填 | 载荷类型，见各节定义（`user_query` / `kb_clue_set` / `code_location_set` / `repo_timeline` / `jira_reasons` / `synthesis` / `verification` / `final_report`） |
| `chunkInfo` | object | 可选 | **分片输出**：当产出列表型字段（如 `locations[]` / `timeline[]` / `conclusions[]` / `tickets[]`）超过 5 条时，产出方可按 5 条/片分片发送，避免单次载荷过大挤占上下文窗口。结构见 chunkInfo 表 |
| `payload` | object | 必填 | 该类型的具体结构，见对应小节 |

> 实现提示：`queryId` 由 dongmei-ma 在接收用户疑问时生成；其余 agent 透传，不得改写。`round` 由其统一维护、其余透传。

### 1.1 分片通信（chunkInfo）

当产出 agent 的列表型字段（`locations[]` / `timeline[]` / `conclusions[]` / `tickets[]`）超过 5 条时，**建议分片发送**（每片 5 条），避免单条消息过大挤占上下文窗口。

```json
{
  "chunkId": "loc-set-1",
  "chunkIndex": 0,
  "totalChunks": 3
}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `chunkId` | string | 必填 | 同一次 payload 分片的唯一标识，收发两端用此关联各片 |
| `chunkIndex` | number | 必填 | 当前分片序号（从 0 起） |
| `totalChunks` | number | 必填 | 总分片数。末片判定：`chunkIndex = totalChunks - 1` |

**分片规则**（runtime-spec 为权威载体）：

| 规则 | 内容 |
| --- | --- |
| 触发阈值 | 列表字段超过 **5 条**时建议分片（每片 5 条），**非强制**——agent 自判；<5 条可不带 `chunkInfo` |
| 每片载荷 | 独立、自包含。列表字段只含本片的条目；非列表共有字段（如 `sourceMode`/`reposInvolved`/`sourcesPresent`/`regexUsed`）在**首片**携带，后续片可省略 |
| 末片到齐 | `chunkIndex = totalChunks - 1` → 接收方（dongmei-ma）知道已收齐，开始合并 |
| 归并职责 | **dongmei-ma 承担**：缓存 key = `queryId + chunkId`（内存暂存），每收到一片将列表字段 append 到缓存；末片到齐后合并所有分片为完整 payload 使用。下游 agent（synthesizer/evidence-verifier）见到的是合并后的完整 payload |
| 缓存清理 | `round` 变更时清空该 `queryId` 的全部缓存分片，防跨轮残留 |
| 不可分片 | `executiveSummary`（synthesis §2.7）不分片——摘要完整且必须一次送达 |
| 下游透明 | dongmei-ma 合并后转发给下游的 payload 不带 `chunkInfo`——下游 agent 无需感知分片

---

## 2. 关键传递物 schema

### 2.1 用户疑问 → dongmei-ma 解析结果（`user_query` / `query_plan`）

dongmei-ma 接收一句自然语言疑问，解析为查询计划。这是编排起点。

```json
{
  "queryId": "q-20260612-001",
  "round": 0,
  "from": "dongmei-ma",
  "to": "kb-keeper",
  "payloadType": "query_plan",
  "payload": {
    "rawQuestion": "为什么订单超时取消的阈值从30分钟改成了15分钟？",
    "intent": "change_reason",
    "scenario": 1,
    "keywords": ["订单", "超时取消", "阈值", "30分钟", "15分钟"],
    "involvesUI": false,
    "figmaLinks": [],
    "expectedOutputs": ["current_state", "timeline", "root_cause"],
    "language": "zh"
  }
}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `rawQuestion` | string | 必填 | 用户原始疑问，原文保留 |
| `intent` | enum | 必填 | 意图分类，建议枚举：`current_state` / `change_reason` / `impact_scope` / `defect_locate` / `regression_trace` / `feature_evaporation` / `interface_dispute` / `tech_debt` / `onboarding`（场景 1~8，可扩展） |
| `scenario` | number | 可选 | 命中的场景编号（1~8，二期 9），仅作分析方法选型提示 |
| `keywords` | array<string> | 必填 | 供 kb-keeper / code-analyst 检索的关键词候选 |
| `involvesUI` | boolean | 必填 | 是否涉及 UI（决定二期是否触发 design-tracer，首版恒处理为 false 分支） |
| `figmaLinks` | array<string> | 可选 | 用户随疑问提供的 Figma 链接（二期用；首版透传不消费） |
| `expectedOutputs` | array<enum> | 必填 | 期望输出维度，取值 `current_state` / `timeline` / `root_cause` / `confidence` |
| `language` | enum(`zh`/`en`) | 必填 | 交付语言，默认 `zh`；`en` 仅当用户显式请求 |

### 2.2 kb-keeper：KB 线索集（`kb_clue_set`）

kb-keeper 是**唯一 KB 读写口**，经 obsidian CLI + Knowlery `/ask` 检索，给出候选线索，**不读源码**。

```json
{
  "queryId": "q-20260612-001",
  "round": 0,
  "from": "kb-keeper",
  "to": "code-analyst",
  "payloadType": "kb_clue_set",
  "payload": {
    "hit": true,
    "clues": [
      {
        "module": "order-service",
        "repoHint": "hdr-delivery-project",
        "paths": ["order-service/src/main/java/.../OrderCancelService.java"],
        "coreClasses": ["OrderCancelService", "OrderTimeoutPolicy"],
        "keywords": ["timeout", "cancel", "threshold"],
        "citation": "queries/2025-08-order-timeout.md#L12",
        "relevance": "high"
      }
    ],
    "priorConclusion": {
      "exists": false,
      "ref": null
    },
    "notes": "KB 命中一条历史结论的相邻线索；无该问题的既有完整结论"
  }
}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `hit` | boolean | 必填 | KB 是否命中线索。`false` → code-analyst 走源码兜底 |
| `clues` | array<object> | 必填(可空) | 候选线索数组；`hit=false` 时为空数组 |
| `clues[].module` | string | 必填 | 候选模块名 |
| `clues[].repoHint` | string | 可选 | 候选所属仓库（供 code-analyst→repo 映射参考，非权威） |
| `clues[].paths` | array<string> | 可选 | 候选文件/路径 |
| `clues[].coreClasses` | array<string> | 可选 | 候选核心类 |
| `clues[].keywords` | array<string> | 可选 | 检索命中的关键词 |
| `clues[].citation` | string | 必填 | KB 出处引用（Knowlery `/ask` 返回的带引用位置），用于可回挂 |
| `clues[].relevance` | enum(`high`/`medium`/`low`) | 必填 | kb-keeper 对该线索相关度的主观分级 |
| `priorConclusion.exists` | boolean | 必填 | KB `queries/` 是否已有该问题的**完整既有结论**（命中则可秒答） |
| `priorConclusion.ref` | string | 可选 | 既有结论的 KB 路径；`exists=true` 时必填 |
| `notes` | string | 可选 | 自由说明 |

> 归属约束：`citation` 必须是 KB 内部引用；kb-keeper 不得返回源码内容（源码读取归 code-analyst）。

### 2.3 code-analyst：定位结果 → repo+模块映射（`code_location_set`）

code-analyst 据 KB 线索**定位 + 解读** core-ng 代码（本地直读 / 远端经 repo-tracer / KB 未命中源码兜底），并**把定位结果映射到具体 repo + 模块**，告知 repo-tracer 涉及哪些仓库。

```json
{
  "queryId": "q-20260612-001",
  "round": 0,
  "from": "code-analyst",
  "to": "repo-tracer",
  "payloadType": "code_location_set",
  "payload": {
    "sourceMode": "local",
    "locations": [
      {
        "repo": "hdr-delivery-project",
        "module": "order-service",
        "filePath": "order-service/src/main/java/app/order/service/OrderCancelService.java",
        "symbol": "OrderCancelService.cancelTimeoutOrder",
        "lineRange": [42, 78],
        "coreNgRole": "Service",
        "entryPoint": {
          "type": "kafka",
          "marker": "implements MessageHandler<OrderTimeoutMessage>; bindSubscribe in OrderServiceApp"
        },
        "interpretation": "超时取消阈值由 OrderTimeoutPolicy.thresholdMinutes 注入，当前值 15；该方法在 Kafka 消费链路末端执行取消。",
        "evidence": [
          {"type": "code", "ref": "order-service/.../OrderCancelService.java#L42-L78"}
        ],
        "needRemoteFetch": false
      }
    ],
    "reposInvolved": ["hdr-delivery-project"],
    "kbMiss": false,
    "fallbackUsed": false
  }
}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `sourceMode` | enum(`local`/`remote`/`mixed`) | 必填 | 代码来源模式（见 `design-source-switching-routing.md`） |
| `locations` | array<object> | 必填 | 定位结果数组 |
| `locations[].repo` | string | 必填 | 该定位点归属仓库（多仓路由依据） |
| `locations[].module` | string | 必填 | 模块名 |
| `locations[].filePath` | string | 必填 | 文件路径（仓库内相对路径） |
| `locations[].symbol` | string | 可选 | 类/方法符号 |
| `locations[].lineRange` | array<number>[2] | 可选 | 行范围 |
| `locations[].coreNgRole` | enum | 可选 | core-ng 角色：`RestEntry` / `KafkaEntry` / `Controller` / `Service` / `QueryService` / `OperationService` / `Repository` / `Domain`（规则集中维护，见 `design-core-ng-recognition.md`） |
| `locations[].entryPoint` | object | 可选 | 若为入口点，记录类型(`rest`/`kafka`)与实际代码标志 |
| `locations[].interpretation` | string | 必填 | 代码解读（现状/事实） |
| `locations[].evidence` | array<evidence> | 必填 | 代码出处（§2.5），`type` 为 `code`；态B 经本地 git 取到的提交可附 `type:commit`（本地 git 合法，见 §5） |
| `locations[].needRemoteFetch` | boolean | 必填 | 该段代码是否需向 repo-tracer 请求远端最新（触发 §7.4 过时判定询问） |
| `reposInvolved` | array<string> | 必填 | 本次查询涉及的全部仓库去重列表 → repo-tracer 据此路由多个 MCP 实例/本地仓 |
| `kbMiss` | boolean | 必填 | KB 是否未命中（true 表示走了源码兜底） |
| `fallbackUsed` | boolean | 必填 | 是否实际使用了源码兜底搜索 |
| `localGitTimeline` | array<object> | 可选 | **态B 本地非过时仓**：code-analyst 经 `Bash`（`git -C <repoPath> log`）直读本地 git 取到的提交片段（每项含 `repo`/`sha`/`author`/`date`/`subject`/`touchedPaths`，**不在此抽工单号**）。供 repo-tracer 直接采用、免重复跑 git log；repo-tracer 据此统一收口产出 `repo_timeline`（抽工单号、多仓合并）。未提供时 repo-tracer 自取兜底。 |
| `kbAlignment` | object | 可选 | **KB 线索匹配审视结论**（`kb_clue_set.hit=true` 时必产；`hit=false`/纯源码兜底时 `verdict=kb_miss` 或省略）。code-analyst 据 KB 线索定位后比对「KB 描述 vs 实际代码」，给匹配度与逐条偏差，供 synthesizer 并入「记录与实现偏差」、verifier 作 KB 可信度注记。结构见 §2.3.2。**硬约束：KB 偏差 ≠ 结论缺证据**——仅作 KB 可信度参考，不作结论出处，不直接触发置信度下调（见 §2.8）。 |
| `kbIncrement` | object | 可选 | **本次调查中 code-analyst 值得沉淀的增量发现**（KB 未覆盖/需修正的细粒度知识）。**不自写 KB**——随本消息上传，由 dongmei-ma 终局归并入 `kb_persist_request.increments[]`（§2.9.1）统一交 kb-keeper。结构见 §2.10。 |

> 归属约束：远端模式下 code-analyst **不直连 GitHub MCP**，通过 `needRemoteFetch=true` + `code_fetch_request`（§2.3.1）请 repo-tracer 取码。**本地 git 历史**（态B）code-analyst 可经 `Bash` 直读本地仓并经 `localGitTimeline` 附给 repo-tracer——本地 git 读取权 code-analyst/repo-tracer 共享，**仅远端 GitHub MCP 独占 repo-tracer**（见 §5）。

#### 2.3.2 KB 匹配审视结论（`kbAlignment`，code-analyst 产）

code-analyst 拿到 `kb_clue_set` 后**先读实际代码**，再比对 KB 线索（模块/路径/核心类/历史结论）与代码现实的一致性——KB 可能粗粒度或过时。审视结论结构化为 `kbAlignment`，**以代码为锚**（runtime-spec §1）：

```json
{
  "assessed": true,
  "verdict": "stale",
  "deviations": [
    {
      "clueRef": "queries/2025-08-order-timeout.md#L12",
      "kind": "value_drift",
      "detail": "KB 记阈值为 30 分钟，实际代码 OrderTimeoutPolicy.thresholdMinutes 已为 15；以代码为准。",
      "codeEvidence": {"type": "code", "ref": "order-service/.../OrderTimeoutPolicy.java#L20"}
    }
  ],
  "notes": "KB 命中模块/路径正确，仅阈值数值过时。"
}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `assessed` | boolean | 必填 | 是否做了 KB 匹配审视（KB 命中且读了代码 → true；纯源码兜底 → false） |
| `verdict` | enum(`consistent`/`partial`/`stale`/`contradicted`/`kb_miss`) | 必填 | 整体匹配度：`consistent`=KB 与代码一致；`partial`=部分覆盖、有未覆盖细节；`stale`=KB 描述已过时（路径/数值/逻辑变更）；`contradicted`=KB 与代码直接矛盾；`kb_miss`=KB 未命中（走源码兜底） |
| `deviations` | array<object> | 必填(可空) | 逐条偏差；`verdict=consistent`/`kb_miss` 时为空数组 |
| `deviations[].clueRef` | string | 必填 | 对应的 KB 线索出处（来自 `kb_clue_set.clues[].citation`） |
| `deviations[].kind` | enum(`path_moved`/`class_renamed`/`logic_changed`/`coverage_gap`/`value_drift`) | 必填 | 偏差类型 |
| `deviations[].detail` | string | 必填 | 「KB 说 X，实际代码是 Y，以代码为准」的具体描述 |
| `deviations[].codeEvidence` | evidence | 必填 | 坐实该偏差的代码出处（`type:code`/态B `commit`），证明结论以代码为锚 |
| `notes` | string | 可选 | 自由说明 |

> 归属约束：`kbAlignment` 是 code-analyst「以代码为锚」原则的结构化落地，**不引入新数据源**——`codeEvidence` 仍是 code-analyst 合法的 code/本地 commit 出处，`clueRef` 引用 kb-keeper 已给的 `citation`，不构成 KB 写动作。

#### 2.3.1 code-analyst → repo-tracer 远端取码请求（`code_fetch_request`）

远端模式 / 过时确认后取最新时使用。

```json
{
  "queryId": "q-20260612-001", "round": 0,
  "from": "code-analyst", "to": "repo-tracer",
  "payloadType": "code_fetch_request",
  "payload": {
    "requests": [
      {"repo": "hdr-delivery-project", "filePath": "order-service/.../OrderCancelService.java", "ref": "HEAD"}
    ]
  }
}
```

repo-tracer 以 `code_fetch_response` 返回 `{repo, filePath, ref, content, fetchedSha}`，code-analyst 再据此完成解读。

### 2.4 repo-tracer：提交时间线 + 抽取工单号（`repo_timeline`）

repo-tracer 是 **Git/GitHub 网关，独占全部 GitHub MCP 实例（远端）**。本地 git 历史读取权与 code-analyst 共享——**态B 本地非过时仓优先采用 code-analyst 随 `code_location_set.localGitTimeline` 附来的本地 git 片段（不重复跑 git log），未附则经 `Bash` 自取兜底**；远端经 GitHub MCP（独占）。无论来源，`repo_timeline` 由 repo-tracer **统一收口产出**，**始终从 commit subject 抽取 Jira 工单号**（默认正则 `^([A-Z]+-\d+)[:\s]`，冒号或空格分隔，本仓 `DELI-\d+`，可配置，容错无号，Revert 提交穿透抽出原号，见 `design-core-ng-recognition.md` §5）。

```json
{
  "queryId": "q-20260612-001",
  "round": 0,
  "from": "repo-tracer",
  "to": "jira-tracer",
  "payloadType": "repo_timeline",
  "payload": {
    "timeline": [
      {
        "repo": "hdr-delivery-project",
        "sha": "a1b2c3d",
        "author": "zhang.san",
        "date": "2025-08-14T10:22:00+08:00",
        "subject": "DELI-4521: 超时取消阈值 30min→15min",
        "ticketIds": ["DELI-4521"],
        "noTicket": false,
        "isRevert": false,
        "touchedPaths": ["order-service/.../OrderTimeoutPolicy.java"],
        "relevance": "primary"
      },
      {
        "repo": "hdr-delivery-project",
        "sha": "c0ffee1",
        "author": "wang.wu",
        "date": "2025-09-01T09:00:00+08:00",
        "subject": "Revert \"DELI-4521: 超时取消阈值 30min→15min\"",
        "ticketIds": ["DELI-4521"],
        "noTicket": false,
        "isRevert": true,
        "touchedPaths": ["order-service/.../OrderTimeoutPolicy.java"],
        "relevance": "primary"
      },
      {
        "repo": "hdr-delivery-project",
        "sha": "e4f5g6h",
        "author": "li.si",
        "date": "2025-06-02T14:05:00+08:00",
        "subject": "重构超时策略读取（无单号）",
        "ticketIds": [],
        "noTicket": true,
        "isRevert": false,
        "touchedPaths": ["order-service/.../OrderTimeoutPolicy.java"],
        "relevance": "context"
      }
    ],
    "ticketIdsAll": ["DELI-4521"],
    "regexUsed": "^([A-Z]+-\\d+)[:\\s]",
    "reposCovered": ["hdr-delivery-project"],
    "shallowWarning": false
  }
}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `timeline` | array<object> | 必填 | 按时间排序的相关 commit |
| `timeline[].repo` | string | 必填 | commit 所属仓库（多仓时区分） |
| `timeline[].sha` | string | 必填 | commit sha（出处锚点） |
| `timeline[].author` | string | 可选 | 作者（缺陷责任/onboarding 场景用） |
| `timeline[].date` | string(ISO8601) | 必填 | 提交时间 |
| `timeline[].subject` | string | 必填 | commit subject 原文 |
| `timeline[].ticketIds` | array<string> | 必填 | 抽取到的工单号；无号时为空数组。正则 `^([A-Z]+-\d+)[:\s]`（冒号或空格分隔，本仓 `DELI-\d+`，可配置，见 `design-core-ng-recognition.md` §5）；Revert 提交从被包裹的原 subject 二次抽出 |
| `timeline[].noTicket` | boolean | 可选 | 标记无号提交（容错）；为 true 时 `ticketIds` 为空 |
| `timeline[].isRevert` | boolean | 可选 | 标记 `Revert "..."` 提交（穿透抽出被 revert 的原工单号填入 `ticketIds`，并置 `isRevert=true`）。支撑场景7功能蒸发追踪 |
| `timeline[].touchedPaths` | array<string> | 可选 | 该 commit 触碰的相关路径 |
| `timeline[].relevance` | enum(`primary`/`context`) | 必填 | 主因 commit vs 上下文 commit |
| `ticketIdsAll` | array<string> | 必填 | 全时间线去重后的工单号集合 → 交给 jira-tracer |
| `regexUsed` | string | 必填 | 本次实际使用的抽取正则（默认/本仓/用户配置，可配置） |
| `reposCovered` | array<string> | 必填 | 本次实际覆盖的仓库（应等于 code-analyst 的 `reposInvolved`，缺失即风险，供 verifier 校验） |
| `shallowWarning` | boolean | 必填 | 是否检测到 shallow clone（本地 git 不能 shallow，缺历史 → 影响置信度） |

> 归属约束：仅 repo-tracer 可调用 GitHub MCP；多仓时每仓对应独立实例 + 独立 token，由 repo-tracer 路由。

### 2.5 出处对象（evidence，复用类型）

贯穿 code-analyst / repo-tracer / jira-tracer / synthesizer 的统一出处结构，是「可回挂出处」原则的载体。

```json
{ "type": "code", "ref": "order-service/.../OrderCancelService.java#L42-L78" }
{ "type": "commit", "ref": "hdr-delivery-project@a1b2c3d" }
{ "type": "jira", "ref": "DELI-4521" }
{ "type": "kb", "ref": "queries/2025-08-order-timeout.md#L12" }
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `type` | enum(`code`/`commit`/`jira`/`kb`) | 必填 | 出处来源类型 |
| `ref` | string | 必填 | 可定位的引用（路径#行 / repo@sha / 工单号 / KB 路径#行） |

### 2.6 jira-tracer：工单业务原因（`jira_reasons`）

jira-tracer 经 **Jira MCP** 取工单业务原因与多工单因果脉络。

```json
{
  "queryId": "q-20260612-001",
  "round": 0,
  "from": "jira-tracer",
  "to": "synthesizer",
  "payloadType": "jira_reasons",
  "payload": {
    "tickets": [
      {
        "id": "DELI-4521",
        "found": true,
        "summary": "缩短订单超时取消阈值至15分钟",
        "type": "Story",
        "status": "Done",
        "businessReason": "运营反馈30分钟占用库存过久，影响周转；A/B 验证15分钟转化更优。",
        "linkedTickets": ["DELI-4400"],
        "resolvedDate": "2025-08-13",
        "evidence": [{"type": "jira", "ref": "DELI-4521"}]
      }
    ],
    "causalChain": "DELI-4400(库存周转优化需求) → DELI-4521(阈值调整实现)",
    "missingTickets": []
  }
}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `tickets` | array<object> | 必填 | 工单详情数组 |
| `tickets[].id` | string | 必填 | 工单号 |
| `tickets[].found` | boolean | 必填 | Jira 中是否查到（false → 计入 `missingTickets`，影响置信度） |
| `tickets[].summary` | string | 可选 | 工单标题 |
| `tickets[].type` | string | 可选 | 工单类型（Story/Bug/Task…） |
| `tickets[].status` | string | 可选 | 工单状态 |
| `tickets[].businessReason` | string | 必填(found=true) | **业务原因**（根因解释核心来源） |
| `tickets[].linkedTickets` | array<string> | 可选 | 关联工单（因果脉络） |
| `tickets[].resolvedDate` | string | 可选 | 解决/关闭日期。来源 REST v3 `fields=resolutiondate` |
| `tickets[].evidence` | array<evidence> | 必填 | 出处，`type` 恒为 `jira` |
| `causalChain` | string | 可选 | 多工单因果脉络的叙述。jira-tracer 须先取主工单 `issuelinks`+`parent`，再经 JQL 二次拉相邻工单组装 |
| `missingTickets` | array<string> | 必填 | 有号但 Jira 未查到的工单（缺口标注用） |

### 2.7 synthesizer：三源综合结论（`synthesis`）

synthesizer 综合 code + git + jira → 结论；**分析方法沉淀为可复用 skill**（按 §5 的 9 类场景）。

```json
{
  "queryId": "q-20260612-001",
  "round": 0,
  "from": "synthesizer",
  "to": "evidence-verifier",
  "payloadType": "synthesis",
  "payload": {
    "executiveSummary": "📋 订单超时取消配置发生过一次变更：\n\n2025年8月14日（DELI-4521），订单超时取消阈值从30分钟改为15分钟。这次变更起源于运营团队提出的缩短库存占用的需求——此前30分钟的等待时间导致商品库存被长时间锁定，影响了库存周转效率（关联需求 DELI-4400）。\n\n变更落地在订单服务的取消逻辑中，将等待时间从30分钟调整到15分钟。这是一个单点数值改动，涉及1个代码提交、1个Jira工单，改动范围可控，不涉及上下游接口变化。\n\n综合来看，这次调整本质上是业务策略的优化——运营侧通过验证确认15分钟在用户体验和库存效率之间取得了更好的平衡，由开发侧执行了参数调整。当前线上订单取消超时策略已以15分钟为准。",
    "scenario": "change_reason",
    "analysisMethod": "change-reason-tracing-v1",
    "conclusions": [
      {
        "statement": "订单超时取消阈值于2025-08-14由30分钟改为15分钟。",
        "dimension": "current_state",
        "evidence": [
          {"type": "code", "ref": "order-service/.../OrderTimeoutPolicy.java#L20"},
          {"type": "commit", "ref": "hdr-delivery-project@a1b2c3d"}
        ]
      },
      {
        "statement": "变更原因为缩短库存占用、提升周转（运营需求 DELI-4400 派生）。",
        "dimension": "root_cause",
        "evidence": [{"type": "jira", "ref": "DELI-4521"}]
      }
    ],
    "timelineNarrative": "2025-06 重构策略读取(无单号) → 2025-08-14 DELI-4521 调整阈值。",
    "sourcesPresent": {"code": true, "git": true, "jira": true},
    "unknowns": []
  }
}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `executiveSummary` | string | 必填 | **面向非技术人员的自然语言结论摘要**：用纯业务语言将 Jira 业务原因与代码变化的高层影响编织为连贯叙事。默认避免技术标识（类名/方法名/字段名）；代码与 Jira 有出入时例外允许暴露以定位差异。以一段简述式结尾收官。帮助产品经理/测试快速理解结论，再决定是否深入看 `conclusions[]` 全部细节 |
| `scenario` | enum | 必填 | 对应分析场景（同 `intent` 枚举） |
| `analysisMethod` | string | 必填 | 所用分析方法 method id，命名 `<scene-slug>-v1`（如 `change-reason-tracing-v1`）；全部 method 收于单一项目级 skill `synthesis-core`（`.claude/skills/synthesis-core/`，单 skill 多 method），见 `design-synthesis-and-verification.md` §2/§8 |
| `conclusions` | array<object> | 必填 | 结论数组 |
| `conclusions[].statement` | string | 必填 | 结论文本 |
| `conclusions[].dimension` | enum | 必填 | 维度：`current_state` / `timeline` / `root_cause` |
| `conclusions[].evidence` | array<evidence> | 必填 | **每条结论必须挂出处**（核心原则） |
| `timelineNarrative` | string | 可选 | 演变时间线叙述 |
| `sourcesPresent` | object{code,git,jira:boolean} | 必填 | 三源是否齐备（verifier 置信度判据的直接输入） |
| `unknowns` | array<string> | 必填 | synthesizer 自认的未决/推断点（供 verifier 重点校验） |

### 2.8 evidence-verifier：出处校验 + 置信度 + 缺口（`verification`）

evidence-verifier 校验每条结论是否挂着 `代码/commit/工单` 出处 + 输出**置信度（高/中/低）** + 不足时**触发发散返工**。

```json
{
  "queryId": "q-20260612-001",
  "round": 0,
  "from": "evidence-verifier",
  "to": "dongmei-ma",
  "payloadType": "verification",
  "payload": {
    "verdict": "sufficient",
    "confidence": "high",
    "perConclusion": [
      {"statement": "订单超时取消阈值...改为15分钟。", "hasEvidence": true, "evidenceTypes": ["code","commit"], "ok": true},
      {"statement": "变更原因为...", "hasEvidence": true, "evidenceTypes": ["jira"], "ok": true}
    ],
    "gaps": [],
    "divergeHints": [],
    "boundaryViolations": []
  }
}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `verdict` | enum(`sufficient`/`insufficient`) | 必填 | 证据是否充分。`insufficient` → dongmei-ma 决定是否发散返工（§7） |
| `confidence` | enum(`high`/`medium`/`low`) | 必填 | 置信度，判据见 §7.2 |
| `perConclusion` | array<object> | 必填 | 逐结论校验 |
| `perConclusion[].hasEvidence` | boolean | 必填 | 是否挂了出处 |
| `perConclusion[].evidenceTypes` | array<enum> | 必填 | 实际具备的出处类型 |
| `perConclusion[].ok` | boolean | 必填 | 该结论是否通过校验 |
| `gaps` | array<object> | 必填 | 缺口标注；`insufficient` 或 `confidence<high` 时必有内容 |
| `gaps[].missingSource` | enum(`code`/`git`/`jira`) | 必填 | 缺哪一源 |
| `gaps[].whichConclusion` | string | 必填 | 关联到哪条结论 |
| `gaps[].detail` | string | 必填 | 缺口细节（降级交付时直接呈现给用户） |
| `divergeHints` | array<enum> | 必填 | **发散重派建议项**，取值自 §7.3 可枚举清单；`verdict=sufficient` 时为空 |
| `boundaryViolations` | array<object> | 必填 | **三道防线校验层的运行期可审计兜底输出**：标记引用了产出方「允许使用的 MCP 服务」声明范围外数据来源的结论；无违规时为空数组 `[]`。命中则该结论置信度**下调**并记入 `gaps`（见 `evidence-verifier.md` §C） |
| `boundaryViolations[].whichConclusion` | string | 必填 | 越界结论标识（关联到 `perConclusion[].statement`） |
| `boundaryViolations[].detail` | string | 必填 | 越界详情：该结论引用的数据来源落在产出方「允许使用的 MCP 服务」声明范围外 |
| `kbNote` | string | 可选 | **KB 可信度注记**（来自 code-analyst 的 `code_location_set.kbAlignment`）。当 `kbAlignment.verdict ∈ {stale, contradicted, partial}` 时，verifier 在此**仅作记录**「本次 KB 线索与实际代码有偏差（KB 可能过时），结论已以代码为锚坐实」。**红线（必须遵守）：KB 陈旧 / 偏差 ≠ 结论证据不足——不触发 `verdict=insufficient`、不下调 `confidence`、不进 `gaps`、不触发返工**；KB 偏差只说明 KB 旧了、本次靠源码而非靠 KB 坐实，结论本身的三源充分性独立判定。 |

> 逐结论校验规则、三级置信度判据细化（含 shallow/漏仓/missingTickets 等下调因素）、`gaps` 完整结构（`missingLink`/`suggestedHint`）与「缺环→发散 hint」映射、synthesizer 9 类场景分析方法，见权威定稿 `design-synthesis-and-verification.md`。

### 2.9 dongmei-ma：最终交付报告（`final_report`）

dongmei-ma 是编排与用户接口层，**不直连任何信息源**；归并上游产物，默认产出中文报告。

```json
{
  "queryId": "q-20260612-001",
  "round": 1,
  "from": "dongmei-ma",
  "to": "user",
  "payloadType": "final_report",
  "payload": {
    "language": "zh",
    "currentState": "...",
    "timeline": "...",
    "rootCause": "...",
    "confidence": "high",
    "degraded": false,
    "gaps": [],
    "evidenceIndex": [
      {"type": "commit", "ref": "hdr-delivery-project@a1b2c3d"},
      {"type": "jira", "ref": "DELI-4521"}
    ],
    "roundsUsed": 1,
    "kbPersisted": true,
    "kbRef": "queries/2026-06-order-timeout-threshold.md"
  }
}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `language` | enum(`zh`/`en`) | 必填 | 交付语言，默认 zh |
| `currentState` | string | 必填 | 当前实现状态（代码现实） |
| `timeline` | string | 必填 | 演变时间线（含关联工单号） |
| `rootCause` | string | 必填 | 根因解释（Jira 业务原因）；降级时可为「证据不足」声明 |
| `confidence` | enum(高/中/低) | 必填 | 最终置信度（取自 verifier 末轮） |
| `degraded` | boolean | 必填 | 是否降级交付（2 轮返工后仍不足） |
| `gaps` | array | 必填 | 降级时标注的具体缺口（缺哪一源/哪一环） |
| `evidenceIndex` | array<evidence> | 必填 | 全报告出处索引 |
| `roundsUsed` | number | 必填 | 实际发散返工轮次（0~2） |
| `kbPersisted` | boolean | 必填 | 是否已沉淀回 KB（充分交付时 true） |
| `kbRef` | string | 可选 | 沉淀回 KB 的路径 |

> 沉淀动作由 dongmei-ma **委托 kb-keeper** 执行（`/cook` 按 SCHEMA 编译写入 `queries/`，中文 + 英文摘要）；dongmei-ma 自身不写 KB。

#### 2.9.1 dongmei-ma → kb-keeper 沉淀请求（`kb_persist_request`）

```json
{
  "queryId": "q-20260612-001", "round": 1,
  "from": "dongmei-ma", "to": "kb-keeper",
  "payloadType": "kb_persist_request",
  "payload": {
    "rawQuestion": "...",
    "report": { "currentState": "...", "timeline": "...", "rootCause": "...", "confidence": "high" },
    "evidenceIndex": [ {"type":"commit","ref":"hdr-delivery-project@a1b2c3d"} ],
    "writeMode": "cook",
    "degraded": false,
    "gaps": [],
    "increments": [
      {
        "from": "code-analyst",
        "namespace": "modules/hdr-delivery-project/order-service",
        "kind": "kb_deviation",
        "summary": "OrderTimeoutPolicy 阈值由 30→15（KB 旧值已校正）",
        "detail": "...",
        "evidence": [{"type":"code","ref":"order-service/.../OrderTimeoutPolicy.java#L20"}]
      }
    ]
  }
}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `writeMode` | enum(`cook`/`degraded_note`) | 必填 | `cook`=权威结论写 `queries/`；`degraded_note`=轻量降级记录 |
| `degraded` | boolean | 必填 | 降级交付为 true；kb-keeper 据此区分写入区，不混入权威结论 |
| `gaps` | array | 可选 | 降级时随附的缺口（写入轻量记录的「缺口」部分） |
| `increments` | array<kbIncrement> | 可选 | **多 agent 增量发现归并集**（§2.10）：dongmei-ma 终局把 code-analyst / repo-tracer / jira-tracer 随各自产物上报的 `kbIncrement` 收集于此，统一交 kb-keeper。kb-keeper **以 `append` 写入各 `namespace`（`modules/`/`entrypoints/`）细粒度增量**，与 `queries/` 权威结论区分（写法见 §2.10）。空/缺省表示本次无增量。 |

- 充分交付：`writeMode=cook`、`degraded=false`，kb-keeper 以 `/cook` 编译沉淀权威结论，回 `{persisted:true, ref:"queries/..."}`。
- 降级交付（§7.5）：`writeMode=degraded_note`、`degraded=true`，kb-keeper 写「问题+已知线索+缺口」轻量记录并标 degraded，**与权威结论区分**，检索时不当已定论返回。
- 两种情形**都触发**沉淀。
- **`increments` 与主结论沉淀同批触发、同步执行**：无论充分/降级，dongmei-ma 都把已归并的 `increments` 随 `kb_persist_request` 交 kb-keeper；增量发现是经全链路（含 evidence-verifier 校验）后的产物，不在调查中途旁路写 KB（终局统一归并，保 KB 写独占 kb-keeper + 防并发竞态）。

### 2.10 多 agent 增量发现（`kbIncrement`，code-analyst / repo-tracer / jira-tracer 产）

为「知识增量积累」（细粒度知识库建设），三个调查 agent 在本次查询中各自把**值得沉淀的发现**作为产物**可选字段 `kbIncrement`** 随消息上报。**它们绝不自写 KB**（KB 写独占 kb-keeper）——dongmei-ma 终局归并进 `kb_persist_request.increments[]`（§2.9.1）统一交 kb-keeper `append`。

```json
{
  "from": "repo-tracer",
  "namespace": "entrypoints/hdr-delivery-project",
  "kind": "new_commit_clue",
  "summary": "DELI-4521 阈值调整 commit；另见 Revert 蒸发线索 c0ffee1",
  "detail": "...",
  "evidence": [{"type":"commit","ref":"hdr-delivery-project@a1b2c3d"}]
}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `from` | enum(`code-analyst`/`repo-tracer`/`jira-tracer`) | 必填 | 增量发现的产出 agent |
| `namespace` | string | 必填 | 建议落库命名空间（`modules/<repoSlug>/<module>` 或 `entrypoints/<repoSlug>`），供 kb-keeper 定位 append 目标；最终路径由 kb-keeper 据真实 vault 约定校准 |
| `kind` | enum | 必填 | 发现类型：code-analyst→`kb_deviation`/`new_entrypoint`/`new_callchain_node`/`repo_mapping_fix`；repo-tracer→`new_commit_clue`/`ticket_id_clue`/`revert_evaporation`/`shallow_warning`；jira-tracer→`business_reason`/`linked_ticket_chain`/`missing_ticket` |
| `summary` | string | 必填 | 一句话增量摘要（中文，供 append 增量条目） |
| `detail` | string | 可选 | 细节正文 |
| `evidence` | array<evidence> | 必填 | 出处（各 agent 合法来源：code-analyst→code/本地 commit；repo-tracer→commit；jira-tracer→jira），保「增量可回挂」 |

> 形态说明：各 agent 的 `kbIncrement` 形态——
> - **code-analyst**：KB 偏差（来自 `kbAlignment.deviations`，可直接复用）、KB 未覆盖的新入口点/调用链节点、repo+模块映射修正。
> - **repo-tracer**：KB 线索之外新出现的关键 commit / 工单号、Revert 蒸发线索、shallow 警告。
> - **jira-tracer**：工单业务原因、`linkedTickets` 因果链、`missingTickets`。
>
> 归属约束：`kbIncrement` 仅是**产物字段上报**，不是 KB 写动作——三 agent `tools` 白名单不含任何 KB 写路径，写库仍唯一收口 kb-keeper（见 §5、§8）。evidence-verifier 不校验 `kbIncrement`（它不参与结论出处，仅作沉淀素材）。

---

## 3. 全链路数据流（一图）

```
user ──rawQuestion──▶ dongmei-ma
                         │ query_plan
                         ▼
                     kb-keeper ──kb_clue_set──▶ code-analyst
                                                   │ (远端: code_fetch_request ⇄ repo-tracer)
                                                   │ code_location_set (reposInvolved)
                                                   ▼
                                              repo-tracer ──repo_timeline(ticketIdsAll)──▶ jira-tracer
                                                   ▲                                          │ jira_reasons
                                  (独占 GitHub MCP)│                                          ▼
                                                   │                                     synthesizer ──synthesis──▶ evidence-verifier
                                                   │                                                                     │ verification
                                                   │                                                                     ▼
                                                   │                                                                 dongmei-ma
                                                   │                                              sufficient │        │ insufficient
                                  ◀── 发散重派(round+1, ≤2) ────────────────────────────────────────────────┘        │ 交付 + kb_persist_request──▶ kb-keeper
```

> 注（teammate 形态）：上图为**逻辑数据流**。实际承载方式是 **dongmei-ma 作为协调者 teammate，经共享任务列表 + 消息（SendMessage）驱动**——各 agent 的产物以消息形式发出、对协调链路相关 teammate 可见，dongmei-ma 据此推进下一环。`from→to` 表示消息的产出方与目标 teammate（经消息/共享子任务流转）。

---

## 4. 双源切换在契约中的体现

过时判定按**「被检索到的相关代码」粒度**，非整仓比较：

- code-analyst 对每个 `location` 给出 `needRemoteFetch`：仅当本地存在仓库、且 repo-tracer 报告该段远端版本更新时为 true。
- repo-tracer 通过 `code_fetch_response` 附带 `localSha` / `remoteSha` 对比结果（`staleness` 字段：`fresh`/`stale`/`no_local`）。
- `staleness=stale` 时，dongmei-ma 就**该段代码**向用户发起询问（是否取最新），用户决策后 code-analyst 据返回的 content 重做该段解读。多仓时逐仓判定。

`code_fetch_response`（repo-tracer → code-analyst）追加字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `staleness` | enum(`fresh`/`stale`/`no_local`) | 该段代码本地 vs 远端 |
| `localSha` / `remoteSha` | string | 对比锚点 |
| `content` | string | 取到的代码内容（远端模式或确认取最新时） |

> 完整字段（`results` 数组、`remoteLatestCommit`、`notes`、态 C 用户交互、多仓路由、漏仓兜底）与流程时序见权威定稿 `design-source-switching-routing.md`；本节为骨架，双源/路由细节以该文档为准。

---

## 5. 角色归属约束

下列约束是**契约级硬约束**，违反即视为实现缺陷，由 evidence-verifier 把关：

| 约束 | 契约体现 |
| --- | --- |
| **GitHub MCP（远端）独占 repo-tracer** | 仅 repo-tracer 产出 `repo_timeline` / `code_fetch_response`，统一收口提交时间线；**其他 agent 的 payload 中不得出现直接 GitHub MCP（远端）调用结果**。code-analyst 远端取码与远端提交历史必须经 `code_fetch_request`。**本地 git 历史读取权 code-analyst/repo-tracer 共享**（态B 经 `Bash` 直读本地仓）：code-analyst 可经 `localGitTimeline` 附本地 git 片段，repo-tracer 信任采用并收口；独占只针对**远端 GitHub MCP**，不针对本地 git。 |
| **KB 读写独占 kb-keeper** | 仅 kb-keeper 产出 `kb_clue_set`、消费 `kb_persist_request`；其他 agent 不产出 `type:kb` 之外的 KB 写动作，读 KB 也不得绕过。code-analyst 的 evidence 含 `code` 与（态B 本地 git 的）`commit`，**不含 `kb`**。 |
| **dongmei-ma 不直连信息源** | dongmei-ma 的输入仅来自其他 agent 的 payload + 用户；其 payload 不含 `code`/`commit`/`jira`/`kb` 的一手获取动作，只做归并、调度、返工决策、交付。 |
| **远端模式 code-analyst 经 repo-tracer 取码** | 见 §2.3.1；`sourceMode∈{remote,mixed}` 时 `locations[].evidence` 的 code 内容来源必须可追溯到一次 `code_fetch_request`。 |
| **跨仓路由** | `reposInvolved`（code-analyst）→ `reposCovered`（repo-tracer）应一致；不一致由 verifier 标为缺口（漏仓风险）。 |

---

## 6. core-ng 识别约定在契约中的落点

- `code_location_set.locations[].coreNgRole` 与 `.entryPoint` 是 core-ng 识别结果的载体。
- 识别规则集中在一处维护（`skills/coreng-recognition/SKILL.md`），契约只约定其输出枚举，不约定识别逻辑——便于后续扩展其他框架时只增枚举、不改契约。
- `entryPoint.marker` 字段记录目标仓库实际代码标志，当官方约定与实际不符，以实际为准。

### 6.1 样本仓库识别要点

| 识别对象 | 实际标志 | 对契约的影响 |
| --- | --- | --- |
| **REST 入口（形态一）** | `*WebService` 接口在 `{service}-interface` 模块 `api/` 包，注解 import 自 `core.framework.api.web.service.*`；实现 `{service}/web/*WebServiceImpl`，装配 `api().service(Xx.class, bind(XxImpl.class))` | `coreNgRole=RestEntry` |
| **REST 入口（形态二）** | `Controller` + `http().route(HTTPMethod.X, path, controller::method)` | 同 `RestEntry`；两种形态规则表都要覆盖 |
| **Kafka 入口** | `implements MessageHandler<T>`（import `core.framework.kafka.MessageHandler`），类在 `kafka/` 包，注册 `{Service}App.bindSubscribe()` → `kafka().subscribe(Topic, Msg.class, bind(Handler.class))` | `coreNgRole=KafkaEntry` |
| **调用链/装配** | `@Inject`（`core.framework.inject.Inject`）注入 Service；Service 细分 `QueryService` / `OperationService` / `CreationService` | `coreNgRole` 枚举含 `CreationService` |
| **存储（双形态）** | 同时存在 `db().repository(X.class)`（MySQL 风格）与 `config(MongoConfig).collection(X.class)`（Mongo） | 规则表须覆盖两种；`coreNgRole=Repository` 可细分 marker 区分 db/mongo |
| **工单号** | subject 开头 `DELI-\d+`，分隔符冒号或空格皆有；已见无号提交与 Revert | 正则 `^([A-Z]+-\d+)[:\s]` |
| **扫描排除** | `frontend/` 含 `node_modules` 须排除；`utility/` 为库模块 | code-analyst 源码兜底/遍历时须排除 |

详见 `design-core-ng-recognition.md`。

---

## 7. 编排契约：校验返工循环

### 7.1 循环状态机（dongmei-ma 驱动）

```
round=0 起算
  收到 verification:
    ├─ verdict=sufficient        → 交付(final_report) + 委托 kb-keeper 沉淀 → 结束
    └─ verdict=insufficient
         ├─ round < 2            → 选取**有新增维度的**有效 divergeHints 执行发散重派, round+1
         │                          (无新增维度的重派=无效返工, 不 +1; 凑不出增量则直接降级)
         └─ round == 2 (已用满)   → 降级交付: final_report.degraded=true, 标注 gaps, confidence=low/中
                                    (不再沉淀完整结论, 见 §7.5)  → 结束
```

要点：
- **teammate 形态语义**：状态机由 **dongmei-ma 作为协调者 teammate 驱动**。文中「发散重派」「委托 kb-keeper 沉淀」「回到 code-analyst 段」均指 **dongmei-ma 经消息（SendMessage）/ 共享子任务**通知相关 teammate 开展新一轮工作。状态机判定逻辑、round 计数、≤2 轮上限均不变。
- **round 从 0 起，最大 2**，即最多 2 次「发散重派」（首轮 round0 + 返工 round1 + 返工 round2 = 共 3 次综合机会；「2 轮发散返工」指 round1、round2 两次重派）。
- 每轮发散重派由 dongmei-ma 依据 verifier 的 `divergeHints` + `gaps` 选择具体动作（§7.3），不得无策略空转。
- 降级交付照常出报告，**明确声明「证据不足」并标注具体缺口**（缺哪一源/哪一环），不臆造结论。

> 轮次口径：「round0=首次综合，round1/round2=两次发散返工，最多 3 次综合」，即**发散重派最多 2 次**。

### 7.2 置信度判据

verifier 依据 `synthesis.sourcesPresent` + 逐结论出处计算：

| 条件 | 置信度 |
| --- | --- |
| 三源（code + git + jira）齐备**且互相印证**，每条结论均挂出处 | **高** |
| 缺 Jira 业务原因，或仅有 git 时间线（code+git 但无 jira 因果） | **中** |
| 结论主要依赖推断、缺直接出处（含关键结论无 evidence） | **低** |

附加降级因素（下调一档或标注）：`shallowWarning=true`、`reposCovered ⊊ reposInvolved`（漏仓）、`missingTickets` 非空。

### 7.3 「发散重派」可枚举清单（防空转，对齐点 core-dev①）

verifier 在 `divergeHints` 中给建议，dongmei-ma 据 `gaps.missingSource` 选取执行。这是一张**按维度可枚举的递进策略表**：每个条目都标注「相对上一轮新增的是哪一类证据/范围」，dongmei-ma 据此逐级展开（而非笼统「再搜一次」）。每轮可组合多项：

| hint 枚举 | 触发缺口 | **相对上一轮新增维度**（防空转关键） | 发散动作（dongmei-ma 重派给谁） |
| --- | --- | --- | --- |
| `widen_kb_search` | 线索不足/相关度低 | **新增检索范围**：放宽后的关键词集 / 新命中的相邻 `queries/` | 重派 kb-keeper：放宽关键词、`/ask` 改写 query、检索相邻 `queries/` |
| `kb_to_source_fallback` | KB 未命中或线索空 | **新增证据来源**：从「依赖 KB」切到「源码兜底」这一新来源 | 指示 code-analyst 走源码兜底（`fallbackUsed=true`），不依赖 KB |
| `expand_code_scope` | 定位点过窄/漏调用链 | **新增调用链节点/路径**：上下游 Controller↔Service↔Repository 中本轮新纳入的符号/文件 | 重派 code-analyst：沿 core-ng 调用链上下扩展，扩大符号/路径范围 |
| `add_repos` | `reposCovered` 缺仓 / 跨服务隐性调用 | **新增仓库**：本轮补入 `reposInvolved` 的、上一轮未覆盖的 repo | 重派 code-analyst 重做 repo+模块映射补齐 `reposInvolved`；repo-tracer 增加路由仓库 |
| `extend_git_history` | 时间线过短/疑似 shallow | **新增时间范围/历史深度**：加深的 commit 窗口 / 取消 shallow 后新得的历史 | 重派 repo-tracer：加深历史、扩大 commit 检索窗口（按路径 `git log --follow` 等价） |
| `relax_ticket_regex` | 大量 `noTicket` / 抽不到号 | **新增抽取范围**：从 subject 扩到 commit body / 放宽正则新命中的工单号 | 重派 repo-tracer：放宽/调整抽取正则（仍可配置），扫描 commit body 而非仅 subject |
| `chase_linked_tickets` | jira 业务原因缺失/单薄 | **新增工单关联**：顺 `linkedTickets`/parent 追到的、上一轮未取的上游工单 | 重派 jira-tracer：顺 `linkedTickets` 追因果链上游工单 |
| `retry_missing_tickets` | `missingTickets` 非空 | **新增检索方式**：对查不到的工单改用 JQL/换 key 形式等新途径 | 重派 jira-tracer：对查不到的工单换检索方式/确认工单号抽取是否误差 |
| `reframe_synthesis` | 结论与证据不匹配/推断过多 | **新增分析视角**：换用不同场景分析 method / 重新对齐三源（非重复同一综合） | 重派 synthesizer：换分析方法 skill、降低推断、明确 `unknowns` |

> **防空转判据（硬约束）**：每一轮发散返工**必须有「相对上一轮新增的搜索/源/范围」**——即上表「新增维度」列至少有一项相对上轮确有增量。**任何一轮若只重复上一轮的搜索动作而无新增维度，即视为无效返工，不计入 ≤2 轮额度**（不消耗 round，也不前进——dongmei-ma 必须换出有增量的 hint，否则直接降级交付）。
>
> 落地：dongmei-ma 在发起每轮重派前，比对本轮拟用 hint 的「新增维度」与上一轮已执行维度的差集；差集为空则该 hint 作废、另选。`round` 计数**仅对「有新增维度的有效返工」+1**（契约 §7.1）；verifier 跨轮对比 `gaps` 收敛性辅助判断。
>
> 其他约束：每轮发散**必须至少选 1 项有效（有新增维度）hint** 且**针对 verifier 标注的缺口**；若 `divergeHints` 为空但 `verdict=insufficient`，dongmei-ma 按 `gaps.missingSource` 兜底映射（code→expand_code_scope/add_repos；git→extend_git_history/relax_ticket_regex；jira→chase_linked_tickets/retry_missing_tickets）。同一维度连续两轮无改善 → 换其他维度；第二轮仍不足 → 干净降级交付并标注缺口（契约 §7.1）。

### 7.4 返工时的信封语义

- 发散重派时 dongmei-ma 发出的下游 payload `round` 设为新轮次值；下游透传。
- verifier 对比同 `queryId` 跨轮的 `gaps`，若缺口未收敛可在 `divergeHints` 中提示「换策略」。

### 7.5 降级交付与沉淀策略

- 充分交付（`sufficient`，置信度高/中）：必沉淀权威结论（`kb_persist_request`，`writeMode=cook`，写 `queries/` 权威区）。
- **降级交付（2 轮后仍 `insufficient`）：仍写 KB，但只写一条轻量记录「问题 + 已知部分线索 + 明确缺口」，标 `degraded=true`，不写进权威结论区**。落地：
  - `kb_persist_request` 增字段 `degraded:true` / `writeMode=degraded_note`（§2.9.1）；kb-keeper 据此**区分写入**：degraded 记录用独立标记与权威结论隔离。
  - **查询期约束**：`/ask` 命中 degraded 记录时**不得当权威结论秒答**，须显式提示「该问题上次查询证据不足、卡在 <缺口>」，仅作「已知线索 + 缺口」参考。
  - **SCHEMA 承载**：degraded 区分依赖 KB SCHEMA 能表达「权威 vs degraded」类型/粒度。

---

## 8. 角色与 payloadType 归属总表

| agent id | 消费(输入 payloadType) | 产出(输出 payloadType) | 信息源归属 |
| --- | --- | --- | --- |
| `dongmei-ma` | `user`原始疑问 / `verification` / 各 agent 产物（含各 agent `kbIncrement`） | `query_plan` / `final_report` / `kb_persist_request`（终局归并 `increments[]`）/ 返工重派指令 | 编排层，**不直连信息源** |
| `kb-keeper` | `query_plan` / `kb_persist_request`（含 `increments[]`） | `kb_clue_set` / 沉淀确认（`queries/` 主结论 + `modules/`/`entrypoints/` 增量 append） | **唯一 KB 读写**（obsidian CLI + Knowlery `/ask` `/cook`） |
| `code-analyst` | `kb_clue_set` / `code_fetch_response` | `code_location_set`（含态B `localGitTimeline`、`kbAlignment`、`kbIncrement`）/ `code_fetch_request` | 代码内容（本地直读 / 远端经 repo-tracer）+ **态B 本地 git 历史（经 `Bash`，与 repo-tracer 共享）** |
| `repo-tracer` | `code_location_set`（取用态B `localGitTimeline`）/ `code_fetch_request` | `repo_timeline`（含 `kbIncrement`）/ `code_fetch_response` | 本地 Git（与 code-analyst 共享）/ **独占多个 GitHub MCP 实例（远端）** |
| `jira-tracer` | `repo_timeline`(ticketIdsAll) | `jira_reasons`（含 `kbIncrement`） | **Jira MCP** |
| `synthesizer` | `code_location_set`（含 `kbAlignment`）+`repo_timeline`+`jira_reasons` | `synthesis` | 上游三源产物 |
| `evidence-verifier` | `synthesis`(+全链路产物，含 `kbAlignment`) | `verification`（含 `kbNote`） | 上游全部产物 |
| `design-tracer`（二期） | UI 相关 + figmaLinks | 设计上下文 payload（二期定义） | Figma MCP（二期） |

---
