# 马冬梅计划 — core-ng 识别规则定稿（真实样本核验）

| 项目 | 内容 |
| --- | --- |
| 文档类型 | 设计定稿（core-ng 识别约定 + 真实样本核验证据） |
| 适用产品 | 马冬梅计划（dm-seek） |
| 关联 PRD | `D:\dev_repository\CT-hackathon\dm-seek\docs\马冬梅计划-PRD.md`（v0.3 §8.2 / §8.3） |
| 关联契约 | `design-agent-io-schema.md` §6.1（coreNgRole 枚举、code_location_set） |
| 核验样本 | `D:\dev_repository\hdr-delivery-project`（core-ng 多模块微服务，git 历史完整） |
| 版本 | v1.0（已实地核验，待 critic 审视 T7） |
| 日期 | 2026-06-12 |
| 负责人 | core-dev |
| 状态 | 待审视 |

> 本文是 core-ng 识别规则的**单一权威定稿**，供 code-analyst 实现任务（#11）直接依赖。每条约定均附**样本仓真实出处**（文件路径 + 行号 / commit），落实 PRD §8.3「双重落地」与「以代码实际标志为准」。规则集中维护形态见 §6。

---

## 0. 核验方法与样本概况

- 方法：直接读取样本仓 `hdr-delivery-project` 真实源码与 git 历史，对 PRD §8.2 每条约定**举具体实例坐实**；同时对照 core-ng 官方约定（`https://github.com/neowu/core-ng-project` wiki / 源码 / DeepWiki），冲突时以样本实际代码为准。
- 样本模块布局（`settings.gradle.kts`，已核）：
  - `backend/`：每个服务一组 `{service}-service` + `{service}-service-interface` + `{service}-service-{db|mongo|es}-migration` 配对。服务含 delivery-task-v2、delivery-search、delivery-agent、delivery-supply、external-delivery-provider、external-delivery-simulator、delivery-scheduler 等。
  - `frontend/`：dispatch-portal-site（前端站点，**扫描须排除 node_modules**）。
  - `utility/`：relay/onfleet/nash/doordash/map/grubhub/genai/test/gcloud-storage/devcycle 等**库模块**（非服务入口，定位时按需而非入口遍历）。
- 包结构：`app.{domain}` 下按业务域分（task/job/courier/alert/eta/doordash/...），每域含 `domain/` `service/` `web/` `kafka/` 子包。

---

## 1. REST 入口

core-ng 有**两种** REST 入口形态，样本仓两种都在用，规则表须**都覆盖**。

### 1.1 形态一：WebService 接口 + 实现（主流，已坐实）

**约定标志**：
- 接口：`{service}-service-interface` 模块 `app.{domain}.api` 包下的 `*WebService` 接口；方法注解 `@GET/@POST/@PUT/@PATCH/@DELETE` + `@Path` + `@PathParam`，注解 **import 自 `core.framework.api.web.service.*`**（非 JAX-RS、非 Spring）。
- 实现：`{service}-service` 模块 `app.{domain}.{subdomain}.web` 包下的 `*WebServiceImpl implements XxWebService`。
- 装配：在 `{Service}App` 中 `api().service(XxWebService.class, bind(XxWebServiceImpl.class))`。

**样本出处（坐实）**：
- 接口：`backend/delivery-task-v2-service-interface/src/main/java/app/deliverytask/api/TaskWebService.java`
  - import：`core.framework.api.web.service.{GET,POST,PUT,PATCH,DELETE,Path,PathParam}`（L28-34）。
  - 实例：`@POST @Path("/task/wonder") WonderCreateTaskResponse createWonderTask(...)`（L40-42）；`@GET @Path("/task/:orderId/route-tracking") ...`（L64-66，路径参数 `:orderId` + `@PathParam`）。
  - 同一 interface 模块共 25 个 `*WebService` 接口（Glob 实测）。
- 实现：`backend/delivery-task-v2-service/src/main/java/app/deliverytask/task/web/TaskWebServiceImpl.java`
  - `public class TaskWebServiceImpl implements TaskWebService`（L44）。
- 装配：`backend/delivery-task-v2-service/src/main/java/app/deliverytask/DeliveryTaskServiceApp.java`
  - `api().service(TaskWebService.class, bind(TaskWebServiceImpl.class))`（L224）。

> 注意：实现类包路径是 `{domain}.{subdomain}.web`（如 `app.deliverytask.task.web`），不是顶层 `web/`；定位 Impl 时按 `implements XxWebService` 搜索更稳，而非仅靠包名。

### 1.2 形态二：Controller + http().route（已坐实）

**约定标志**：
- 普通类（无需实现接口），方法签名 `public Response method(Request request)`（来自 `core.framework.web.Request` / `core.framework.web.Response`）。
- 装配：`http().route(HTTPMethod.X, "/path", controller::method)`（`core.framework.http.HTTPMethod`）。

**样本出处（坐实）**：
- Controller：`backend/delivery-task-v2-service/src/main/java/app/deliverytask/doordash/controller/DoordashBusinessStoreInitController.java`
  - 方法：`public Response initBusiness(Request ignoreRequest)`（L67）、`createStore(Request request)`（L98）、`syncHDRAddressAndPhoneNumber(...)`（L114）。
- 装配：`DeliveryTaskServiceApp.configureDoordashBusinessCreationRoute()`（L409-420）
  - `http().route(HTTPMethod.POST, "/_app/doordash/businesses/init", doordashController::initBusiness)`（L417）等 4 条。
- 其他 Controller 实例：delivery-search 的 `ReIndexJobController`、external-delivery-provider 的 `RelayWebhookController`、delivery-agent 的 `GetRcaSchemaController` 等（Glob 实测多服务均有）。

> 与 PRD §8.2 表述差异：PRD 写「`Controller.execute(Request)`」。**样本实际不用统一的 `execute` 方法名**，而是任意方法名 + `controller::method` 方法引用注册；识别应以 **`http().route(... , controller::method)` 注册点** + **方法签名 `Response m(Request)`** 为准，不依赖 `execute` 字面名。（偏离点①，规则已据实修正。）

---

## 2. Kafka 入口（已坐实）

**约定标志**：
- 处理器：`implements MessageHandler<T>`（**import `core.framework.kafka.MessageHandler`**，**非** `@KafkaListener`、非 Spring），类在 `app.{domain}.kafka` 包，方法 `void handle(String key, T message)`。
- 注册：`{Service}App.bindSubscribe()` 中 `kafka().subscribe(Topic, Message.class, bind(XxHandler.class))`；也存在按需命名的独立 consumer：`kafka("name").subscribe(...)`（独立 groupId）。

**样本出处（坐实）**：
- 处理器：`backend/delivery-task-v2-service/src/main/java/app/deliverytask/kafka/KitchenOrderMessageHandler.java`
  - `public class KitchenOrderMessageHandler implements MessageHandler<KitchenOrderMessage>`（L16，import `core.framework.kafka.MessageHandler` L9）。
  - `public void handle(String s, KitchenOrderMessage message)`（L23）。
- 注册：`DeliveryTaskServiceApp.bindSubscribe()`（L353-388）
  - 默认 consumer：`kafka().subscribe(KOMServiceTopics.KITCHEN_ORDER_TOPIC, KitchenOrderMessage.class, bind(KitchenOrderMessageHandler.class))`（L366）。
  - 命名 consumer（独立 groupId）：`kafka("task-updated-kafka").subscribe(DeliveryTaskV2Topic.DELIVERY_TASK_UPDATED, ..., bind(DeliveryTaskV2UpdatedMessageHandler.class))`（L354-357）。
  - 本 App 共约 28 个 `subscribe(...)`（实测）。

> 识别要点：以 **`implements MessageHandler<T>`** 为类级标志（最可靠），以 **`{Service}App.bindSubscribe()` 内的 `subscribe(Topic, Msg, bind(Handler))`** 为「topic ↔ message ↔ handler」三元映射来源。

---

## 3. 调用链与装配（已坐实）

**约定标志（链路）**：
```
WebServiceImpl / Controller / MessageHandler   (入口层)
        │  @Inject (core.framework.inject.Inject)
        ▼
Service 层：QueryService / OperationService / CreationService / *BaseQueryService 等
        │  @Inject
        ▼
Repository<T> (core.framework.db.Repository, MySQL 风格)  /  MongoCollection<T> (Mongo)
        ▼
Domain（@Entity / @Collection 注解的领域类）
```
- 装配：依赖经 `@Inject` 字段注入；对象在 `{Service}App` 或各 `Module` 中 `bind(X.class)` / `bind(new X(...))`、`load(new XxModule())` 注册。

**样本出处（坐实）**：
- 入口→Service：`TaskWebServiceImpl`（task/web/TaskWebServiceImpl.java）
  - `@Inject TaskOperationService` / `TaskQueryService` / `TaskCreationService` / `TaskUpdateAddressOperationService` / `TaskForceCompleteService`（L45-54，import `core.framework.inject.Inject` L35）。
  - 方法委派：`createWonderTask` → `taskCreationService.createWonderTask(request)`（L66）。
- Handler→Service：`KitchenOrderMessageHandler` `@Inject KitchenOrderService` / `TaskBaseQueryService`，`handle()` 委派 `kitchenOrderService.handleOrderMessage(...)`（L17-20, L40）。
- Service→Repository：`app/deliverytask/task/service/TaskBaseQueryService.java`
  - `@Inject Repository<Task> taskRepository`、`Repository<TaskItem>` 等（L32-45，import `core.framework.db.Repository` L17）。
- Service 三分实证：`task/service/` 下 `TaskQueryService` / `TaskOperationService` / `TaskCreationService` / `TaskForceCompleteService` / `TaskStatusUpdateService` / `TaskTrackingOperationService` / `TaskUpdateAddressOperationService` / `TaskBaseQueryService` 八个并存（Glob 实测）。
- 装配点：`DeliveryTaskServiceApp.bindBaseService()`（L306-334）逐个 `bind(...)`；`loadModule()`（L192-219）`load(new XxModule())`。

**遍历可行性结论**：从 `{Service}App` 出发可静态遍历——`api().service(...)` 给全部 REST 入口、`bindSubscribe()` 给全部 Kafka 入口、`http().route(...)` 给全部 Controller 路由；再沿入口类的 `@Inject` 字段递归即可重建调用链至 Repository/MongoCollection。这是 KB 初始化（PRD §7.2「沿入口类及调用链建库」）与 code-analyst 定位的可行基础。

---

## 4. 存储层（双形态，重要——相对 PRD 的补充）

PRD §8.2 仅写「Repository / MongoCollection」，**样本实际并存两套**，规则表须都覆盖（偏离点②）：

| 存储形态 | 注册标志（在 App） | 注入标志（在 Service） | 样本出处 |
| --- | --- | --- | --- |
| **MySQL 风格** | `db().repository(X.class)` / `db().view(X.class)` | `@Inject Repository<X>`（`core.framework.db.Repository`） | `DeliveryTaskServiceApp.bindDB()` L237-266；`TaskBaseQueryService` L32-45 |
| **MongoDB** | `config(MongoConfig.class).collection(X.class)` / `.view(X.class)` | `@Inject MongoCollection<X>`（`core.framework.mongo.MongoCollection`） | `DeliveryTaskServiceApp.bindCollection()` L268-304（`var config = config(MongoConfig.class)` L269）；`DoordashBusinessStoreInitController` import `core.framework.mongo.MongoCollection` L28 |

> 识别区分：`db().repository/view` ↔ Repository（MySQL）；`config(MongoConfig).collection/view` ↔ MongoCollection（Mongo）。本样本主存储为 Mongo + 部分 MySQL，与 PRD §8.1「Mongo 主 / MySQL」一致。

---

## 5. Commit 工单号格式（已坐实，相对 PRD O3 有偏离）

**样本真实 git log（最近 30 条，已核）**：

| 现象 | 实例 | 结论 |
| --- | --- | --- |
| 主流：`DELI-\d+` + **冒号**分隔 | `DELI-4520:Fixed the issue...` | 匹配 PRD O3 |
| **空格**分隔变体 | `DELI-4512 Non-test type HDR...`、`DELI-4489 Parallel Search...` | **偏离点③**：分隔符**冒号或空格都有**，正则不能只认冒号 |
| 无号提交 | `update external api version`、`update publish api version` | 验证 repo-tracer **容错无号**（PRD O3） |
| Revert | `Revert "DELI-4503:ADK Java 1.3..."` | 支撑**功能蒸发追踪**场景（PRD §5 场景 7）；抽号需能从 Revert 包裹中取出原号 |
| 框架升级可定位 | `DELI-4511:upgrade coreNG to 5.0.4` | core-ng 版本变更可经 commit 定位 |

**定稿正则建议**（供 repo-tracer #12 落地，PRD O3「可配置正则、默认此式」）：
- 工单号本体：`[A-Z]+-\d+`，本仓默认 `DELI-\d+`。
- 位置：commit **subject 开头**，后接**冒号或空格**再接描述 → 抽取正则 `^([A-Z]+-\d+)[:\s]`；Revert 场景再就引号内 subject 二次抽取。
- 容错：无匹配 → 标 `noTicket`，不报错（契约 `repo_timeline.timeline[].noTicket`）。

---

## 6. 规则集中维护形态（可扩展）

**结论：识别规则集中在 code-analyst 专用 skill 内的单一规则文件**（T11 已定稿落于 `skills/coreng-recognition/SKILL.md`，skill 标准入口），契约层（`design-agent-io-schema.md` §6.1）只约定输出枚举 `coreNgRole`，识别逻辑全部收于此文件。扩展到其他框架时**只新增规则段 + 新增枚举值，不改契约、不散落到各 agent**。

规则文件的建议结构（每类一段，字段化便于机读/扩展）：

```yaml
framework: core-ng
version_marker: "DELI-4511:upgrade coreNG to 5.0.4 → 5.0.4"   # 版本可由 commit 定位
exclude_paths: ["frontend/**/node_modules/**", "**/build/**"]   # 扫描排除
entry_points:
  rest_webservice:
    interface: { module_suffix: "-service-interface", pkg: "app.*.api", type: "interface *WebService",
                 annotations_import: "core.framework.api.web.service.*", verbs: [GET,POST,PUT,PATCH,DELETE] }
    impl:      { type: "class *WebServiceImpl implements *WebService", pkg: "app.*.*.web" }
    wiring:    "api().service(Xx.class, bind(XxImpl.class))"
  rest_controller:
    marker_method: "Response m(Request)"            # 不依赖 execute 字面名
    wiring: "http().route(HTTPMethod.X, path, controller::method)"
  kafka_handler:
    type: "class *Handler implements MessageHandler<T>"   # import core.framework.kafka.MessageHandler
    pkg: "app.*.kafka"
    wiring: "{Service}App.bindSubscribe(): kafka([name]).subscribe(Topic, Msg.class, bind(Handler.class))"
call_chain:
  inject_marker: "@Inject (core.framework.inject.Inject)"
  service_layer: [QueryService, OperationService, CreationService, "*BaseQueryService"]
  storage:
    mysql:  { wiring: "db().repository/view(X.class)",            inject: "Repository<X> (core.framework.db.Repository)" }
    mongo:  { wiring: "config(MongoConfig).collection/view(X.class)", inject: "MongoCollection<X> (core.framework.mongo.MongoCollection)" }
  domain: "@Inject 注入的实体/集合泛型 X"
ticket:
  regex: "^([A-Z]+-\\d+)[:\\s]"        # 冒号或空格分隔
  repo_default: "DELI-\\d+"
  isRevert: "bool；Revert 提交穿透抽出被 revert 的原工单号填 ticketIds，并置 isRevert=true（key 名 isRevert，与 T1 §2.4 / issuekey 规格一致）"
  tolerate_no_ticket: true
```

> 上为规则**载体形态**示意（字段化、单文件、可增段）；具体落库由 code-analyst 实现任务 #11 据本定稿固化。识别时**官方约定作补充印证、目标仓库实际标志为准**（PRD §8.3）。

---

## 7. 目标仓库相对官方约定的偏离点汇总（PRD §8.3 要求记录）

| # | 维度 | PRD §8.2 / 官方惯例表述 | 样本实际（权威） | 规则处置 |
| --- | --- | --- | --- | --- |
| ① | Controller 形态 | `Controller.execute(Request)` | 任意方法名 + `http().route(..., controller::method)`，签名 `Response m(Request)` | 以 route 注册点 + 签名识别，不认 `execute` 字面名 |
| ② | 存储 | Repository / MongoCollection（并列） | **MySQL `db().repository` 与 Mongo `config(MongoConfig).collection` 双形态并存** | 规则表两套都覆盖，区分注入类型 |
| ③ | 工单号分隔符 | subject 开头**冒号**分隔 | 冒号**或空格**均出现 | 正则 `^([A-Z]+-\d+)[:\s]` 容两种 |
| ④ | WebServiceImpl 包位 | （PRD 示意 `{service}/web/`） | 实为 `app.{domain}.{subdomain}.web`，非顶层 web | 以 `implements *WebService` 为主判据，不强依赖包名 |
| ⑤ | 扫描范围 | 未提排除 | `frontend/node_modules`、`build/` 须排除；`utility/` 为库非入口 | 规则 `exclude_paths` + 入口遍历只针对 backend 服务 |

> 以上偏离均「以目标仓库实际代码为准」处理，已并入 §6 规则载体。无与官方约定根本冲突项；core-ng 版本（5.0.4）可由 `DELI-4511` commit 定位，便于后续按版本校准官方语料。

---

## 8. 对契约文档的回填项（已同步 / 待 code-analyst 落实）

- `design-agent-io-schema.md` §6.1 已据本核验补 `coreNgRole` 枚举 `CreationService`、存储双形态、frontend 排除——与本定稿一致。
- 待 #11 落实：把 §6 规则载体固化为 code-analyst skill 内单文件；§5 正则交 #12 repo-tracer 落地。

## 9. 开放点（**全部已由 tech-lead 裁定，2026-06-12**）

1. ~~KB-init 入口双形态枚举~~ **已裁定（确认）**：KB 初始化遍历入口须**同时枚举 WebService 形态①与 Controller 形态②**——作为对 T15（KB-init skill）的硬要求。
2. ~~Revert 二次抽号~~ **已裁定（采纳）**：默认从 `Revert "..."` 抽出被 revert 的工单号并标 `isRevert=true`（字段名与 T1 §2.4 一致；支撑功能蒸发场景）；已同步 T12 repo-tracer 锁定为默认行为。
3. ~~规则文件落点命名~~ **已定稿（T11）**：`skills/coreng-recognition/SKILL.md`（项目级 `.claude/skills/`，skill 标准入口；契约层只约定 `coreNgRole` 枚举、规则集中此处）。
