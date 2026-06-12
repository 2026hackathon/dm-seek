---
name: coreng-recognition
description: core-ng 框架代码识别规则集（单一权威规则文件）——REST 入口(WebService 接口 + Controller 两形态)、Kafka 入口(MessageHandler + bindSubscribe)、调用链(@Inject → Service → Repository/MongoCollection → Domain)、存储双形态、工单号格式、扫描排除。供 code-analyst 定位 core-ng 代码时引用。识别以目标仓库实际标志为准、官方约定作补充印证。当需要在 core-ng 仓库里识别入口/调用链/存储/角色时使用。
---

# coreng-recognition — core-ng 识别规则（集中维护、单文件可扩展）

> 本 skill 是 core-ng 识别规则的**单一权威载体**，内容固化自 `docs/design-core-ng-recognition.md`（已对样本仓 `hdr-delivery-project` 实地核验）。code-analyst 定位代码时引用本规则；扩展到其他框架时**只新增规则段 + 新增 `coreNgRole` 枚举**，不改契约、不散落到各 agent。
>
> **总则（PRD §8.3 双重落地）**：识别**以目标仓库实际代码标志为准**，官方 wiki 约定作补充印证；当官方约定与实际不符，以实际为准。每条规则均给出「实际标志」与「样本出处」两栏。

## 何时用

- code-analyst 收到 KB 线索或走源码兜底、需把代码定位到具体 `coreNgRole` / `entryPoint` 时。
- KB 初始化（kb-init skill）枚举入口点 + 沿调用链展开时（REST 两形态都要枚举，硬要求）。

## 0. 扫描排除与遍历范围（先做，避免误定位）

| 项 | 规则 |
| --- | --- |
| `exclude_paths` | `frontend/**/node_modules/**`、`**/build/**` 必须排除（含大量第三方/产物） |
| `frontend/` | 前端站点（如 dispatch-portal-site），非 core-ng 后端入口，入口遍历不进 |
| `utility/` | 库模块（relay/onfleet/nash/map/genai/test/… ），**非服务入口**，按需定位而非入口遍历 |
| 入口遍历范围 | 仅 `backend/` 下 `{service}-service` 各服务 |

包结构约定：`app.{domain}` 下按业务域分（task/job/courier/alert/eta/...），每域含 `domain/` `service/` `web/` `kafka/` 子包。

## 1. REST 入口（两形态，规则表都覆盖）→ `coreNgRole=RestEntry`

### 形态一：WebService 接口 + 实现（主流）

| 维度 | 实际标志（权威） |
| --- | --- |
| 接口 | `{service}-service-interface` 模块 `app.{domain}.api` 包下的 `*WebService` 接口；方法注解 `@GET/@POST/@PUT/@PATCH/@DELETE` + `@Path` + `@PathParam`，注解 **import 自 `core.framework.api.web.service.*`**（非 JAX-RS、非 Spring） |
| 实现 | `{service}-service` 模块 `app.{domain}.{subdomain}.web` 包下的 `*WebServiceImpl implements XxWebService`（**注意是 `{domain}.{subdomain}.web`，非顶层 `web/`**） |
| 装配 | `{Service}App` 中 `api().service(XxWebService.class, bind(XxWebServiceImpl.class))` |
| `entryPoint.marker` | 记 `api().service(XxWebService.class, bind(XxWebServiceImpl.class))` 的**实际行**（含文件:行号） |

样本出处：接口 `backend/delivery-task-v2-service-interface/.../app/deliverytask/api/TaskWebService.java`（import L28-34，`@POST @Path("/task/wonder")` L40-42，`@GET @Path("/task/:orderId/route-tracking")` L64-66）；实现 `.../app/deliverytask/task/web/TaskWebServiceImpl.java`（`implements TaskWebService` L44）；装配 `DeliveryTaskServiceApp.java` L224。

> **定位 Impl 的稳妥判据：按 `implements XxWebService` 搜索**（Grep `class \w+ implements \w*WebService`），不强依赖包名（偏离点④：包路径是 `app.{domain}.{subdomain}.web` 而非顶层 web）。

### 形态二：Controller + http().route

| 维度 | 实际标志（权威） |
| --- | --- |
| 类 | 普通类（无需实现接口），方法签名 `public Response method(Request request)`（`core.framework.web.Request` / `core.framework.web.Response`） |
| 装配 | `http().route(HTTPMethod.X, "/path", controller::method)`（`core.framework.http.HTTPMethod`） |
| `entryPoint.marker` | 记 `http().route(...)` 注册行 |

样本出处：`.../app/deliverytask/doordash/controller/DoordashBusinessStoreInitController.java`（`public Response initBusiness(Request ignoreRequest)` L67）；装配 `DeliveryTaskServiceApp.configureDoordashBusinessCreationRoute()` L409-420。

> **偏离点①**：PRD 旧表述 `Controller.execute(Request)`，样本**不用统一 `execute` 方法名**。识别以 **`http().route(..., controller::method)` 注册点** + **方法签名 `Response m(Request)`** 为准，不认 `execute` 字面名。

## 2. Kafka 入口 → `coreNgRole=KafkaEntry`

| 维度 | 实际标志（权威） |
| --- | --- |
| 处理器 | `class *Handler implements MessageHandler<T>`（**import `core.framework.kafka.MessageHandler`**，非 `@KafkaListener`、非 Spring），类在 `app.{domain}.kafka` 包，方法 `void handle(String key, T message)` |
| 注册 | `{Service}App.bindSubscribe()` 内 `kafka().subscribe(Topic, Msg.class, bind(XxHandler.class))`；命名 consumer（独立 groupId）`kafka("name").subscribe(...)` |
| `entryPoint.marker` | 记 `subscribe(Topic, Msg.class, bind(Handler.class))` 实际行（即 topic↔message↔handler 三元映射来源） |

样本出处：`.../app/deliverytask/kafka/KitchenOrderMessageHandler.java`（`implements MessageHandler<KitchenOrderMessage>` L16，`handle(...)` L23）；注册 `DeliveryTaskServiceApp.bindSubscribe()` L353-388（默认 consumer L366、命名 consumer L354-357）。

> 类级最可靠标志 = `implements MessageHandler<T>`；用 Grep `implements\s+MessageHandler<` 全仓找处理器，再到 `bindSubscribe()` 取三元映射。

## 3. 调用链与装配（沿 @Inject 递归）

```
入口层(WebServiceImpl / Controller / MessageHandler)
   │  @Inject (core.framework.inject.Inject)
   ▼
Service 层：QueryService / OperationService / CreationService / *BaseQueryService
   │  @Inject
   ▼
存储层：Repository<T>(MySQL) / MongoCollection<T>(Mongo)
   ▼
Domain（@Entity / @Collection 领域类）
```

| 维度 | 实际标志（权威） | coreNgRole |
| --- | --- | --- |
| 装配/注入 | `@Inject`（`core.framework.inject.Inject`）字段注入；对象在 `{Service}App` / `Module` 中 `bind(X.class)` / `load(new XxModule())` 注册 | — |
| Service 细分 | 类名后缀 `QueryService` / `OperationService` / **`CreationService`** / `*BaseQueryService` | `QueryService` / `OperationService` / `CreationService` / `Service` |
| 入口委派 | 入口类 `@Inject` 上述 Service，方法体委派 service 调用 | — |

样本出处：`TaskWebServiceImpl` `@Inject TaskOperationService/TaskQueryService/TaskCreationService` L45-54，`createWonderTask → taskCreationService.createWonderTask` L66；`task/service/` 下八个 Service 并存；装配 `DeliveryTaskServiceApp.bindBaseService()` L306-334。

> 遍历可行性：从 `{Service}App` 出发可静态遍历——`api().service(...)` 给全部 REST 入口、`bindSubscribe()` 给全部 Kafka 入口、`http().route(...)` 给全部 Controller 路由；再沿入口类 `@Inject` 字段递归重建调用链至存储层。这是 KB-init 与 code-analyst 定位的基础。

## 4. 存储层（双形态，都覆盖）→ `coreNgRole=Repository`（marker 区分）

| 存储形态 | 注册标志（App） | 注入标志（Service） | marker 区分 |
| --- | --- | --- | --- |
| **MySQL 风格** | `db().repository(X.class)` / `db().view(X.class)` | `@Inject Repository<X>`（`core.framework.db.Repository`） | marker 记 `db().repository/view` |
| **MongoDB** | `config(MongoConfig.class).collection(X.class)` / `.view(X.class)` | `@Inject MongoCollection<X>`（`core.framework.mongo.MongoCollection`） | marker 记 `config(MongoConfig).collection/view` |

样本出处：MySQL `DeliveryTaskServiceApp.bindDB()` L237-266 + `TaskBaseQueryService` L32-45；Mongo `bindCollection()` L268-304。

> **偏离点②**：PRD 仅写「Repository / MongoCollection」，样本**两套并存**。`coreNgRole=Repository` 不细分枚举，靠 `entryPoint.marker` / `interpretation` 区分 db 还是 mongo（注入类型为准）。Domain 角色 = `@Inject` 注入的实体/集合泛型 X（`@Entity` / `@Collection`）。

## 5. Commit 工单号格式（供解读时关联，repo-tracer 抽取主责）

| 现象 | 实例 | 处置 |
| --- | --- | --- |
| 冒号分隔（主流） | `DELI-4520:Fixed the issue...` | 匹配 |
| **空格**分隔（偏离点③） | `DELI-4512 Non-test type...`、`DELI-4489 Parallel Search...` | 正则须容空格 |
| 无号 | `update external api version` | 容错，标 `noTicket`，不报错 |
| Revert | `Revert "DELI-4503:ADK Java 1.3..."` | 穿透引号二次抽出原号、标 `isRevert=true`（功能蒸发场景7） |
| 框架升级可定位 | `DELI-4511:upgrade coreNG to 5.0.4` | core-ng 版本可由 commit 定位 |

正则：`^([A-Z]+-\d+)[:\s]`（**冒号或空格**分隔），本仓默认 `DELI-\d+`，可配置。位于 subject 开头。

## 6. `coreNgRole` 输出枚举（契约 §2.3 / §6.1 对齐）

`RestEntry` / `KafkaEntry` / `Controller` / `Service` / `QueryService` / `OperationService` / **`CreationService`** / `Repository` / `Domain`。
（契约层只约定此枚举，识别逻辑全在本文件；扩展框架时增枚举 + 增规则段。）

## 7. 规则机读载体（字段化，便于扩展/校验）

```yaml
framework: core-ng
version_marker: "DELI-4511:upgrade coreNG to 5.0.4 → 5.0.4"
exclude_paths: ["frontend/**/node_modules/**", "**/build/**"]
entry_points:
  rest_webservice:
    interface: { module_suffix: "-service-interface", pkg: "app.*.api", type: "interface *WebService",
                 annotations_import: "core.framework.api.web.service.*", verbs: [GET,POST,PUT,PATCH,DELETE] }
    impl:      { type: "class *WebServiceImpl implements *WebService", pkg: "app.*.*.web", primary_match: "implements *WebService" }
    wiring:    "api().service(Xx.class, bind(XxImpl.class))"
    role: RestEntry
  rest_controller:
    marker_method: "Response m(Request)"            # 不依赖 execute 字面名
    wiring: "http().route(HTTPMethod.X, path, controller::method)"
    role: RestEntry
  kafka_handler:
    type: "class *Handler implements MessageHandler<T>"   # import core.framework.kafka.MessageHandler
    pkg: "app.*.kafka"
    wiring: "{Service}App.bindSubscribe(): kafka([name]).subscribe(Topic, Msg.class, bind(Handler.class))"
    role: KafkaEntry
call_chain:
  inject_marker: "@Inject (core.framework.inject.Inject)"
  service_layer: [QueryService, OperationService, CreationService, "*BaseQueryService"]
  storage:
    mysql:  { wiring: "db().repository/view(X.class)",                inject: "Repository<X> (core.framework.db.Repository)" }
    mongo:  { wiring: "config(MongoConfig).collection/view(X.class)", inject: "MongoCollection<X> (core.framework.mongo.MongoCollection)" }
  domain: "@Inject 注入的实体/集合泛型 X（@Entity / @Collection）"
ticket:
  regex: "^([A-Z]+-\\d+)[:\\s]"        # 冒号或空格分隔
  repo_default: "DELI-\\d+"
  isRevert: "bool；Revert 提交穿透抽出被 revert 的原工单号填 ticketIds，置 isRevert=true"
  tolerate_no_ticket: true
```

## 8. 偏离点速查（PRD §8.3 要求记录，以目标仓库实际为准）

| # | PRD/官方表述 | 样本实际（权威） | 处置 |
| --- | --- | --- | --- |
| ① | `Controller.execute(Request)` | 任意方法名 + `http().route(..., controller::method)`，签名 `Response m(Request)` | 以 route 注册点 + 签名识别 |
| ② | Repository / MongoCollection 并列 | MySQL `db().repository` 与 Mongo `config(MongoConfig).collection` 双形态并存 | 两套都覆盖，按注入类型区分 marker |
| ③ | subject 冒号分隔 | 冒号**或空格**均出现 | 正则 `^([A-Z]+-\d+)[:\s]` |
| ④ | WebServiceImpl 在 `{service}/web/` | 实为 `app.{domain}.{subdomain}.web` | 以 `implements *WebService` 为主判据 |
| ⑤ | 未提排除 | `frontend/node_modules`、`build/` 须排除；`utility/` 库非入口 | `exclude_paths` + 入口遍历仅 backend 服务 |

> 权威依据：`docs/design-core-ng-recognition.md`（含逐条样本出处与 5 项偏离点）、`docs/design-agent-io-schema.md` §6.1（coreNgRole 枚举）、团队记忆 `hdr-delivery-coreng-markers`。
