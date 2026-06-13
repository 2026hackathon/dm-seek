# dm-seek Agent 无响应诊断报告

| 项目 | 内容 |
|---|---|
| 日期 | 2026-06-13 |
| 会话 | q-20260613-001, q-20260613-002 |
| 诊断对象 | code-analyst, repo-tracer |
| 产出方 | dongmei-ma（协调者） |

---

## 现象

在一个 2 小时会话中，7 个 teammate 的表现：

| Teammate | 任务分配 | 实际产出 | 模式 |
|---|---|---|---|
| kb-keeper | 4 次 | 4 次 | 稳定 |
| jira-tracer | 2 次 | 2 次 | 稳定 |
| synthesizer | 1 次 | 自行与 verifier 协作 | 部分 |
| evidence-verifier | 1 次 | 延迟追到 | 部分 |
| **code-analyst** | **4 次** | **0 次** | **系统性无产出** |
| **repo-tracer** | **3 次** | **0 次** | **系统性无产出** |

code-analyst 和 repo-tracer 的行为模式完全相同：
1. Spawn 后成功回报 `ready`（说明能读 agent 定义、能发消息）
2. 收到任务消息后 → 一个 idle notification → 无产出
3. 重复 3-4 次，即使任务缩小到"只读一个文件的 30 行"或"跑一条 git log"也无效

---

## 已排除的假说

| 假说 | 排除依据 |
|---|---|
| tools 白名单缺失 | code-analyst: Read/Grep/Glob/Bash/Skill — 够用。repo-tracer: Bash/Read/mcp__github-* — 够用 |
| 模型差异 | 全部 6 个 teammate 用 claude-opus-4-8，kb-keeper 和 jira-tracer 同样模型但正常 |
| 后端类型 | 全部 `in-process`，正常工作的 agent 同后端 |
| 完全收不到消息 | 两者都成功回报过 ready，证明 spawn → 读定义 → 发消息通路正常 |
| MCP 权限 | repo-tracer 的 mcp__github-hdr-delivery-project 在 tools 白名单中；code-analyst 不需 MCP |

---

## 根因假设（按可能性排序）

### 假说 1：首次任务完成后不轮询新消息（概率最高）

**机制**：spawn 时给定明确 prompt（"读定义 → 回报 ready"），完成首任务后 agent 停止消费 inbox 新消息。每次 idle 表示"当前轮完成"，但不主动检查是否有新 SendMessage 待处理。

**证据**：
- 两者在 spawn 后成功回报 ready（首任务完成）
- 后续 SendMessage 送达 inbox（工具返回 success:true），但 agent 只发 idle 通知，不处理消息内容
- kb-keeper/jira-tracer 同样模式但能持续工作——差异可能在于他们的任务足够简单（CLI 搜索 / MCP 单次查询）能在单轮完成，不需要"跨轮持续处理"的能力

**与官方文档的对照**：Claude Code agent-team 文档描述 teammate 间经 SendMessage + 共享任务列表协作，但未明确说明 teammate 是否会自动轮询 inbox。行为观察指向"不自动轮询"。

### 假说 2：System Prompt 过载

**机制**：两个 agent 的 `.md` 定义均约 85 行，涵盖完整的 I/O 契约、core-ng 识别规则表、双源切换流程、KB 匹配审视规范、增量上报格式、边界声明等。加上 spawn prompt + 任务消息，总 prompt 在首轮可能接近上下文窗口的 60-70%，模型没有足够空间输出分析结果。

**证据**：
- code-analyst.md: 89 行，含完整 core-ng 识别表（7 种角色 + 5 偏离点）、三种取码途径、KB 匹配审视 6 字段契约
- repo-tracer.md: 85 行，含抽号正则、Revert 穿透规则、过时判定 4 态、多仓路由映射、边界用例表引用
- 对照：kb-keeper 的 prompt 同样长但正常工作——差异可能在于 kb-keeper 的任务更聚焦（单次 CLI 调用），不需要像 code-analyst 那样同时追踪调用链 + 填 15+ 字段 + 做 KB 比对

### 假说 3："输出必须合规"导致的静默截断

**机制**：契约要求 code-analyst 产出 `code_location_set`（含 15+ 结构化字段：repo/module/filePath/symbol/lineRange/coreNgRole/entryPoint/interpretation/evidence/needRemoteFetch/kbAlignment/kbIncrement/localGitTimeline…）。Agent 试图一次性产出完整合规输出 → 超出单轮输出 token 限制 → 截断 → 整个回复丢失。

**证据**：
- 给极简任务（"只读一个文件的 30 行，告诉我两个常量的值"）仍然失败——可能是因为即使读到了，agent 也在纠结"要不要套契约格式"
- 成功工作的 kb-keeper 和 jira-tracer 的输出格式更简单：kb_clue_set 是自由文本列表，jira_reasons 是表格式摘要

### 假说 4：Agent 实际产出但回复丢失

**机制**：agent 完成了处理并产出内容，但 in-process 后端未正确将回复投递到会话。

**证据**：
- idle notification 出现时表示 agent 完成了一轮处理
- 极简任务（"读 30 行代码"）在正常情况下不可能"做不出来"
- 需检查 agent 的原始 stdout/stderr 日志才能确认或排除

---

## 建议修复（按成本从低到高）

### 修复 1：添加显式 inbox 轮询指令（针对假说 1）

在 agent 定义的 system prompt 末尾添加：

```markdown
## 消息处理（硬性）
每轮开始时，先检查 SendMessage inbox 是否有来自其他 teammate 的新消息。如有，优先处理消息中的任务；如无，报告 idle 等待。任务完成后再次检查 inbox 是否有新消息再 idle。不要完成一次任务后就永久休眠。
```

**成本**：低（改两行 prompt）
**风险**：不确定 Claude Code teammate 运行时是否支持"检查 inbox"这个动作（SendMessage 投递是推送还是拉取？）。需实测。

### 修复 2：精简 Agent Prompt（针对假说 2）

将当前 85 行的 agent 定义砍到 30 行以内：
- 保留：核心职责（3-5 条）、tools 白名单、边界声明
- 砍掉：详细契约字段表、识别规则表、双源切换流程——改为"详见 `design-*.md`，需要时 Read"
- 砍掉：增量上报细节、KB 审视细节——这些都是"nice to have"，首版先保基本功能

```markdown
# code-analyst（精简版）

## 核心职责
1. 收 kb-keeper 的 kb_clue_set，定位具体代码并解读
2. 向 repo-tracer 产出 code_location_set（定位点 + reposInvolved）
3. 本地代码经 Read/Grep/Glob 直读；远端代码经 repo-tracer 取
4. core-ng 识别规则见 skills/coreng-recognition/SKILL.md

## 输出格式
- locations[]: repo, filePath, symbol, lineRange, interpretation（必填）
- reposInvolved, sourceMode, kbMiss, fallbackUsed（必填）
- 其他字段需要时参考 .claude/rules/design-agent-io-schema.md §2.3

## 边界约束
不调 mcp__github-* / mcp__jira*；不写 KB；远端取码经 repo-tracer。
```

**成本**：中（重写两个 agent 定义）
**收益**：可能解决假说 2+3 两个问题

### 修复 3：拆分任务粒度（针对假说 3）

协调者不再要求一次性产出完整 code_location_set，改为逐步对话：
1. "找 appendWonderSpot 方法 → 只告诉我文件路径和行号"
2. "读这个方法 → 概述逻辑"
3. "追踪它调的 Service → 告诉我注入了什么"
4. 最后汇总

**成本**：低（协调者侧改调度策略，不改 agent 定义）
**收益**：每步 agent 只需产出少量内容，不会被截断

### 修复 4：检查 Agent 输出日志（针对假说 4）

检查 in-process agent 的原始输出，确认是否在产出但被丢弃。路径待确认（可能在工作目录的 `.claude/` 下或临时目录）。

**成本**：低（几分钟查日志）
**收益**：直接确认或排除假说 4

---

## 给工程 Team 的建议执行顺序

1. **先做修复 4**（查日志，5 分钟）——确认 agent 到底有没有产出。如果有产出但丢了 → 后端 bug。如果没有产出 → 继续。
2. **然后做修复 1**（加轮询指令，10 分钟）——改两个 agent .md，重新 spawn 测试最简单任务。
3. **如果仍无效，做修复 2**（精简 prompt，30 分钟）——砍掉 2/3 的内容，重新测试。
4. **修复 3**（拆分任务粒度）是协调者侧的保底策略，不依赖 agent 改动即可生效。

---

## 附录：会话中的实际任务消息样例

### code-analyst 收到的典型任务：
```
queryId: q-20260613-001 | round: 0 | payloadType: kb_clue_set
[6 条 KB 线索，含 module/paths/coreClasses/citation]
请定位源码产出 code_location_set（含 reposInvolved + kbAlignment + localGitTimeline）。
```

### 缩小后的极简任务：
```
只读一个文件的两段（~30行）：CorporateJobCreationService.java 前 50 行 + L418-440
告诉我 APPENDABLE_JOB_STATUSES 和 APPENDABLE_JOB_ORDER_STATUSES 的值
```
→ **仍然无产出**

### repo-tracer 收到的典型任务：
```
queryId: q-20260613-001 | payloadType: code_location_set
[8 个定位点 + 5 个 ticketId 候选]
请产出 repo_timeline
```

### 缩小后的极简任务：
```
取 hdr-delivery-project 仓 CorporateJobCreationService.java 的 git log（最近 10 条）
格式：%h %ad %s --date=short
```
→ **仍然无产出**
