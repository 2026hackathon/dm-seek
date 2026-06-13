# 马冬梅计划 — Agent 间 I/O 契约（轻量版）

> **运行时加载的轻量契约**：仅含各 agent 运行时必需的 0 原则、1 信封结构、8 归属总表。全部详细 schema（JSON 示例 + 完整字段表 + 章节 2-7）见同目录 `design-agent-io-schema-reference.md`，agent 需产出特定载荷时按需 Read。

| 项目 | 内容 |
| --- | --- |
| 文档类型 | 设计契约（agent 间输入/输出 schema + 编排返工循环） |
| 版本 | v0.2 |
| 运行形态 | 路径 B（agent team teammate）：7 agent 平级，dongmei-ma 协调者经任务列表+消息驱动 |

## 0. 约定与说明

- agent 之间是 teammate 间经任务列表+消息的自然语言协作（路径 B，协调非父子委派）。
- **传递形态**：采自然语言为主 + 结构化字段可无歧义提取，不强制贴 JSON 代码块。
- **核心原则**：代码为唯一事实基准；每条结论必须可回挂到 code/commit/jira 出处。

## 1. 公共信封

所有 agent 间载荷共享以下信封字段（dongmei-ma 生成 queryId/维护 round，其余透传不改写）：

```json
{"queryId": "q-20260612-001", "round": 0, "from": "kb-keeper", "to": "dongmei-ma", "payloadType": "kb_clue_set", "payload": {}}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| queryId | string | 必填 | 一次查询唯一 id，贯穿全链路与所有返工轮次 |
| round | number | 必填 | 返工轮次。首轮=0；每次发散重派 +1；上限 2 |
| from/to | enum | 必填 | 产出方/目标 agent id |
| payloadType | enum | 必填 | 载荷类型：user_query/kb_clue_set/code_location_set/repo_timeline/jira_reasons/synthesis/verification/final_report |
| chunkInfo | object | 可选 | 分片输出：列表字段 >5 条时分片发送 |
| payload | object | 必填 | 对应 payloadType 的具体结构（见 reference.md 2.x） |

### 1.1 分片通信

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| chunkId | 必填 | 同次 payload 分片唯一标识 |
| chunkIndex | 必填 | 当前片序号（从 0 起） |
| totalChunks | 必填 | 总分片数。末片：chunkIndex = totalChunks - 1 |

规则：>5 条列表字段建议分片（每片 5 条），agent 自判；dongmei-ma 缓存 key=queryId+chunkId 归并，round 变更时清缓存；executiveSummary 不分片。

### 快捷引用表

| agent | 产出 | 详细 schema |
| --- | --- | --- |
| dongmei-ma | query_plan/final_report/kb_persist_request | reference.md 2.1/2.9/2.9.1 |
| kb-keeper | kb_clue_set | reference.md 2.2 |
| code-analyst | code_location_set/code_fetch_request | reference.md 2.3/2.3.1/2.3.2/2.10 |
| repo-tracer | repo_timeline/code_fetch_response | reference.md 2.4/2.3.1 |
| jira-tracer | jira_reasons | reference.md 2.6 |
| synthesizer | synthesis | reference.md 2.7 |
| evidence-verifier | verification | reference.md 2.8 |
| dongmei-ma to kb-keeper | kb_persist_request | reference.md 2.9.1 |

## 8. 角色与 payloadType 归属总表

| agent id | 消费 | 产出 | 信息源归属 |
| --- | --- | --- | --- |
| dongmei-ma | 用户疑问/verification/各 agent 产物 | query_plan/final_report/kb_persist_request | 编排层，不直连信息源 |
| kb-keeper | query_plan/kb_persist_request | kb_clue_set/沉淀确认 | 唯一 KB 读写 |
| code-analyst | kb_clue_set/code_fetch_response | code_location_set(含 localGitTimeline/kbAlignment/kbIncrement) | 代码内容+态B本地git(Bash，与repo-tracer共享) |
| repo-tracer | code_location_set/code_fetch_request | repo_timeline(含kbIncrement)/code_fetch_response | 本地Git(共享)/独占远端GitHub MCP |
| jira-tracer | repo_timeline(ticketIdsAll) | jira_reasons(含kbIncrement) | Jira MCP(只读) |
| synthesizer | code+repo+jira 三源 | synthesis(含executiveSummary) | 上游三源产物 |
| evidence-verifier | synthesis+全链路产物 | verification(含kbNote/boundaryViolations) | 上游全部产物 |
