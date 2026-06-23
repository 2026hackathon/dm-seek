---
name: kb-init
description: 马冬梅计划知识库初始化——以 core-ng 的 REST 入口(WebService 接口 + Controller 两形态)+ Kafka 入口为种子，沿入口类及调用链类的提交记录 + Jira 做粗粒度建库。可选动作、不设上限、默认全部入口点、支持按服务/模块限定范围、多仓分别初始化。当用户无 KB 或要补充建库时使用。
---

# kb-init — KB 初始化（粗粒度建库）

> 本 skill 是 **dongmei-ma 编排下的一段流程**，**不直接读源码/连 MCP/写库**——各专职动作落到对应 agent，写库一律经 kb-keeper。

## 何时用
- 用户尚无知识库，或希望对某仓/某服务补充建库。**可选、不设硬性上限**，由用户用 scope 控制范围。

## 输入参数
- `repos`：要初始化的仓库（默认全部已配置仓库，多仓**分别**初始化）。**仅处理 repos.json 中已配置 `kb` 字段的仓库**——无 `kb` 表示 KB vault 未创建，需先运行 `windows-setup.ps1` Phase 4。
- `scope`：范围（默认 `all` 全部入口点；可 `service=<名>` / `module=<名>` / `package=<名>` 限定）。
- `maxDepth`：调用链遍历深度上限（默认到 **Repository/Domain 层**止，防大仓链路爆炸；与 coreng-recognition 规则表中「调用链终点=存储层双形态」对齐）。

## Vault 定位

**KB vault 位置从 `.claude/repos.json` 读取**（runtime-spec §12）。每个 repo 的 `kb.vault`（Obsidian vault 名）和 `kb.path`（相对路径）由 windows-setup.ps1 Phase 4 自动写入。无 `kb` 字段的 repo 跳过初始化，回报用户运行 `windows-setup.ps1`。

## 流程（单仓；dongmei-ma 编排，逐 agent 调度）

1. **前置校验**：读 `.claude/repos.json`，过滤出含 `kb` 字段的 repo。若 `repos` 参数指定了 repo 但无 `kb` 字段 → 回报用户该 repo 的 KB vault 未创建。若全部无 `kb` → 终止，提示运行 `windows-setup.ps1`。
2. **范围确定**：默认全部入口点；或按 `scope` 限定。
3. **code-analyst 枚举入口点（种子）**——**REST 两形态都要枚举（硬要求）**：
   - 形态A：`{service}-interface` 模块 `api/` 包的 `*WebService` 接口（`@GET/@POST/@PUT/@PATCH/@DELETE/@Path/@PathParam`，import 自 `core.framework.api.web.service.*`），实现 `{service}/web/*WebServiceImpl`；
   - 形态B：`Controller` + `http().route(HTTPMethod.X, path, controller::method)`；
   - Kafka 入口：`implements MessageHandler<T>`（`core.framework.kafka.MessageHandler`，非 @KafkaListener），注册在 `{Service}App.bindSubscribe()`。
4. **code-analyst 沿调用链展开**：入口 → `@Inject` 注入的 Service（Query/Operation/Creation）→ Repository（`db().repository`）/ Mongo（`config(MongoConfig).collection/.view`，**双存储形态都覆盖**）→ Domain，到 `maxDepth` 止。产出「入口 → 调用链类集合 → repo+模块」清单（粗粒度，不逐行解读）。
5. **repo-tracer 取提交线索**：对清单中类/文件取关键 commit（首次引入/最近修改），抽 Jira 工单号（`^([A-Z]+-\d+)[:\s]`、容错无号、Revert 穿透）。
6. **jira-tracer 取业务原因**：对抽到的工单号取「summary + description 概述」级（建库期不取全量评论/changelog）。
7. **概念提取（自动生成 aliases/keywords）**：kb-keeper 落库前，dongmei-ma 遍历 code-analyst 产出的入口点/调用链清单，对每个入口点自动提取概念映射（runtime-spec §8.2）：
   - **concept 名**：优先取 JavaDoc/commit/Jira summary 中最长的中文名词短语，兜底用入口类名（camelCase 拆词）
   - **aliases**：从 JavaDoc（类/方法注释）、commit subject+body、Jira summary+description 前 200 字符中提取中文短语 + 英文关键词
   - **keywords**：从类名（camelCase 拆词）、方法名（拆词）、@Path/route 路径、包名、调用链下游类名中提取代码符号名
   - 每个 concept 保证 ≥3 个 aliases + ≥5 个 keywords
8. **kb-keeper 落库**：把 (入口/模块/调用链 + commit 线索 + 工单线索) 经 obsidian CLI `create`/`append` 按 SCHEMA 编译为粗粒度条目。`type: entrypoint|module`、`granularity: coarse`、`degraded: false`；**建库期只产中文骨架、不产英文摘要**（英文摘要在条目首次被查询细化时补，合 O9）。
9. **kb-keeper 写 concept-map.md**：将所有 concept 写入 `index/<repoSlug>/concept-map.md`（YAML frontmatter 格式，每 concept 含 id/concept/aliases/repo/module/entries/call_chain/keywords/jira/confidence）。
10. **幂等**：已存在条目 → append/更新，不重复建；记 init 元数据（范围、时间、commit HEAD）到 `_meta/<repoSlug>.init.md`。

## 多仓 / 双源
- **多仓分别 init**，KB 内按 `<repoSlug>/` 命名空间隔离。
- **双源**：研发用户本地仓库（code-analyst 直读）；非研发经 repo-tracer → GitHub MCP 取码。建库期不做过时判定（记 commit HEAD 作基线）。

## 边界
- 本 skill 不直接读源码/连 MCP/写库——编排 code-analyst（入口/调用链）+ repo-tracer（commit+抽号）+ jira-tracer（业务原因）+ kb-keeper（落库）。三条归属约束（KB 写独占 kb-keeper、GitHub MCP 独占 repo-tracer、Jira 独占 jira-tracer）在建库路径上同样成立。
