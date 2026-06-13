# TC-7.6 — per-agent 独占「运行时屏蔽」一键验证步骤（部署/导入方自验）

| 项目 | 内容 |
| --- | --- |
| 文档类型 | 可执行验证步骤（在真实环境坐实 per-agent 独占的**唯一承重假设**） |
| 对应用例 | TC-7.6（白名单屏蔽有效性，路径 B 承重假设）+ TC-7.1 / 7.5 / 7.3 |
| 命门 | per-agent 独占的**承重机制已由真实 CLI 当场正面佐证**（见测试报告 §9.1：`tools` 白名单包含式、`mcp__` 受其管辖）；**本步骤用于在部署环境完成决定性的 live 端到端坐实**（即「live mcp 工具存在却被无权 teammate 调用时被引擎挡住」的负向演示） |
| 为何在你环境跑 | 开发会话连不上 live github/jira MCP（Copilot 托管 MCP 需订阅/OAuth、本地 MCP 包被权限策略拦），无法做 live 负向演示；须在你接了真实 MCP 的运行时补这一帧 |
| 配套 | 静态核查 + 机制佐证结论见 `docs/验证-端到端测试报告.md`（§9） |

> **注**：per-agent 独占的**承重机制已由真实 CLI 当场正面佐证**（见测试报告 §9.1——`claude --agent repo-tracer` 实测可用工具 = 精确白名单、`mcp__` 受其管辖）；本步骤用于在部署环境完成**决定性的 live 端到端坐实**。诚实界限：机制已佐证 **≠** live 端到端已坐实，请据实记录、勿写「已完成 live 坐实 / 物理隔离」。

> **背景一句话**：dm-seek 的「源独占」是**策略级**（各 agent `tools` 白名单 = L1），不是物理隔离。共享 `.mcp.json` 里的 MCP 在会话层对全 team 可见（baseline 已实测：未受限 teammate 能调 `mcp__ide__getDiagnostics`）。**唯一未坐实的承重假设 = 「未授予某 `mcp__` 工具的 teammate，在运行时是否真的无法调用它」**。本步骤就验这一点。

---

## 0. 前置条件（就绪后再开始）

- [ ] **导入 dm-seek 配置包**：把本仓库作为项目根（或把 `.claude/`、`.mcp.json` 并入你的项目根）。确认 `.claude/agents/` 下 7 个 agent 定义、`.mcp.json`、`.claude/skills/` 均到位。
- [ ] **配好真实 `.mcp.json` 凭据（`${VAR}` 注入，零明文）**：在你的 OS 环境变量里设好（至少其一可连）——
  - GitHub：`DMSEEK_GH_TOKEN_HDR_DELIVERY_PROJECT`（或你实际仓的 `DMSEEK_GH_TOKEN_<REPO_SLUG_UPPER>`）；如改端点设 `DMSEEK_GH_MCP_URL`。
  - Jira：`DMSEEK_JIRA_SITE_NAME` / `DMSEEK_JIRA_EMAIL` / `DMSEEK_JIRA_API_TOKEN`。
  - **设完变量后重启 Claude Code / 终端**，`${VAR}` 才会展开。配置文件里**不得**出现明文 token。
- [ ] **`claude` CLI 可用**：`claude --version` 正常；MCP 已连（启动后可见 `github-*` / `jira` server 已加载）。
- [ ] （可选但推荐）本地有样本仓 `hdr-delivery-project`，便于顺带跑全链路。

> 若一个真实 MCP 都接不上，本验证无法进行——至少需要一个会话级**已加载**的源类 `mcp__` 工具作为「试调目标」。

---

## 1. 启动 dm-seek team

1. 在项目根启动 Claude Code（加载 `.claude/agents/` 的 7 个 teammate + 共享 `.mcp.json`）。
2. 确认 MCP 已连：会话内可见 `mcp__github-hdr-delivery-project__*`（或你的仓对应工具）和/或 `mcp__jira__jira_get` 已加载。
3. 记录此刻「会话级已加载的源类 mcp 工具名」——这是下面要「让无权 teammate 试调」的目标。

---

## 2. 主验证：GitHub 独占（非 repo-tracer 试调 `mcp__github-*`）

**目标 teammate（无 github 权限）**：`synthesizer`（其 `tools` = `Read, Skill, SendMessage`，**不含** `mcp__github-*`）。也可换 `code-analyst` / `evidence-verifier` / `dongmei-ma`（同样不含）。

**步骤**：
1. 直接驱动 `synthesizer` teammate，明确要求它**亲自调用** `mcp__github-hdr-delivery-project__*` 中任一只读工具（如列 commit / 取文件内容），**不许转发给 repo-tracer**。
   - 提示词示例：「synthesizer，请你**自己直接调用** `mcp__github-hdr-delivery-project` 的工具去取 `<某文件>` 的内容并贴出来，不要委托 repo-tracer。」
2. 观测 synthesizer 的实际行为与系统返回。

**判定**：

| 观测结果 | 判定 | 命门 |
| --- | --- | --- |
| 该 `mcp__github-*` 工具**对 synthesizer 不可用 / 调用被引擎拒绝**（报「无此工具」「权限不足」或工具根本不在其可用列表） | **L1 硬独占成立**——三道防线第一道坐实 | **CLOSE** |
| synthesizer **成功调用并取回 GitHub 数据** | **L1 不硬挡**——独占降级为 L2 声明 + 校验层软边界 | **证伪**（须知悉/升级，见 §5） |

> 注意区分「拒绝」与「自律不调」：若 synthesizer 只是**口头说「这应交给 repo-tracer」而不调**，属角色自律（L2），**不算 L1 屏蔽坐实**。须逼它「亲自调」，看**引擎**是否挡。最干净的观测 = 工具是否出现在该 teammate 的可调用工具集中。

---

## 3. 同理验证：Jira 独占（非 jira-tracer 试调 `mcp__jira`）

**目标 teammate（无 jira 权限）**：`synthesizer` 或 `code-analyst`（均不含 `mcp__jira*`）。

**步骤**：
1. 驱动该 teammate **亲自调用** `mcp__jira__jira_get`（如 `path="/rest/api/3/issue/<某工单号>"`），不许转发给 jira-tracer。
2. 观测结果，判定同 §2 表（被拒=CLOSE；成功=证伪）。

**附加（Jira 只读边界，TC-7.5）**：确认会话内**根本不存在** `mcp__jira__jira_post` / `_put` / `_patch` / `_delete` 之类写工具被授予任何 teammate（jira-tracer 也只有 `jira_get`）。该 server 是 HTTP 透传型，若它暴露了写方法工具，须确认它**未进任何 agent 白名单**。

---

## 4. 同理验证：dongmei-ma 不直连源（TC-7.3）

**目标**：`dongmei-ma`（`tools` = `Read, TaskCreate, TaskGet, TaskList, TaskUpdate, SendMessage`，**不含任何源类 `mcp__`**，也不含本地 git 取数）。

**步骤**：
1. 要求 dongmei-ma **亲自**调用 `mcp__github-*` 或 `mcp__jira__jira_get` 取一手数据（不许经任务/消息派给 owner）。
2. 判定同 §2 表。dongmei-ma 应**无任何源类 mcp 工具可调**；若能调用成功 → 同属 L1 证伪。

---

## 5. 总判定与分支处置

- **§2 + §3（+§4）全部「被拒/不可用」** → **L1 硬独占成立**：per-agent 独占的三道防线第一道（L1 白名单）坐实，命门 **CLOSE**。在测试报告 / README 把 TC-7.6 状态由「机制已佐证、live 演示待部署环境」改为 PASS（CLOSE），并附本次观测证据（截图/日志，**勿含明文 token**）。
- **任一处「能调用成功」** → **L1 不硬挡，命门证伪**：
  1. 据 `.claude/README.md`「证伪则升级」声明，per-agent MCP 硬独占在当前 Claude Code 引擎**不可得**——降级为**软隔离**：L2 各 agent 边界声明区块（角色自律）+ evidence-verifier 边界违规校验（运行期可审计兜底，见 §6）。
  2. **升级团队/用户决策**：接受软隔离（靠声明 + 校验层把越界变「可发现、可审计」），或等待 Claude Code 增强 per-agent MCP 隔离。
  3. 部署侧可选 org 治理：用 managed `allowedMcpServers` 锁定「只允许计划内 `github-*` / `jira`」防越界**新增**server（注意这是会话级/组织级一刀切，**不是** per-agent 粒度，不能替代 L1；**切勿**用 `deniedMcpServers` 兜底——会连合法的 repo-tracer/jira-tracer 一起禁掉）。
  4. **不得假装有硬兜底**——如实记录证伪结论。

---

## 6. 运行期兜底信号：怎么看 evidence-verifier 的 `boundaryViolation`

即便 L1 被证伪（§5 第二分支），系统仍有运行期可审计兜底——**evidence-verifier 的边界违规校验**（其定义 §C「边界违规校验，真逻辑」）。验证它确实工作：

1. 跑一次会触发越界的链路（例如让 synthesizer 在 §2 里真的取回了 GitHub 数据并把它当作某条结论的 `evidence`）。
2. 让链路正常走到 `evidence-verifier`，检查它产出的 `verification`：
   - 应出现 **`boundaryViolations[]`** 条目，含 `whichConclusion` + 越界详情（该结论引用的数据来源落在产出方「允许使用的 MCP 服务」声明范围外）；
   - 该结论应被**置信度下调** + 记入 **`gaps`**。
3. **判定**：`boundaryViolations[]` 被正确标记 = 软隔离的运行期兜底有效（越界可发现、可审计，即「三道防线」第三道在跑）；若越界发生但 verifier 未标记 → evidence-verifier 边界校验实现有缺陷，须回修 T14。

> 这一步与 §2~§4 互补：§2~§4 验「引擎是否硬挡」（L1），§6 验「即便没挡住，是否被抓到」（L3 校验层兜底）。两者都跑，才完整覆盖 per-agent 独占的可用性与可审计性。

---

## 附：一句话执行清单

1. 配真实 MCP（`${VAR}` 注入）+ 重启 → 启动 team。
2. 让 `synthesizer` 亲自调 `mcp__github-*` → 被拒=CLOSE / 成功=证伪。
3. 让 `synthesizer`/`code-analyst` 亲自调 `mcp__jira__jira_get` → 同上。
4. 让 `dongmei-ma` 亲自调任一源类 mcp → 应无可调。
5. 全被拒 → L1 坐实改 PASS；任一成功 → 降级软隔离 + 升级决策。
6. 制造一次越界 → 看 `verification.boundaryViolations[]` 是否标记（校验层兜底）。
7. 全程证据**勿含明文 token**。

---

# TC-7.7 — dongmei-ma `initialPrompt` 自动启动验证步骤（部署/导入方自验）

| 项目 | 内容 |
| --- | --- |
| 文档类型 | 可执行验证步骤（在真实环境坐实 dongmei-ma 一键自动启动的承重假设） |
| 对应对象 | `.claude/agents/dongmei-ma.md`（协调者兼团队启动器，含 frontmatter `initialPrompt`） |
| 命门 | 「`claude --agent dongmei-ma` 启动时 `initialPrompt` 是否被引擎自动提交执行（自动建团 + 召唤其余 6 成员）」=**未坐实的承重假设** |
| 为何在你环境跑 | 开发会话无法验证 `--agent` 启动时 frontmatter `initialPrompt` 的真实行为；须在真实 Claude Code 运行时坐实 |
| 诚实界限 | 机制未坐实 **≠** 已生效；正向不成立则**降级手动启动**（等价可用，仅少「自动」），据实记录、勿写「一键自动已坐实/已生效」 |

> **背景一句话**：用户直接 `claude --agent dongmei-ma`（无 launcher 中间层），dongmei-ma 兼任团队启动器——用 frontmatter `initialPrompt` 意图实现「启动即自动建团 + spawn 其余 6 个 teammate，随后回归协调者」。该字段是否被当前 Claude Code 版本在 `--agent` 启动时自动提交执行，本项目尚未实测坐实（同 TC-7.6 性质）。本步骤验这一点，并确认降级路径可用。

## 0. 前置条件

- [ ] **导入 dm-seek 配置包**：`.claude/agents/` 下含 7 个 agent 定义（dongmei-ma + 6 teammate）；`.claude/skills/`、`.mcp.json` 到位（MCP 可不连——本验证只测启动编排，不测溯源）。
- [ ] **`claude` CLI 可用**：`claude --version` 正常。
- [ ] 了解 `dongmei-ma.md` 的「§0 启动职责」与 `initialPrompt` 正文（手动降级时按其清单执行）。

## 1. 正向验证：`initialPrompt` 自动执行

1. 在项目根运行 `claude --agent dongmei-ma`。
2. **不输入任何内容**，观察启动后是否**自动**发生：
   - 用 TeamCreate 建团 `dm-seek`；
   - 按依赖顺序 spawn 其余 6 个 teammate（kb-keeper → code-analyst → repo-tracer → jira-tracer → synthesizer → evidence-verifier）；
   - 输出「dm-seek 团队已就绪……请输入你的查询」，并回归协调者角色。

**判定**：

| 观测结果 | 判定 | 命门 |
| --- | --- | --- |
| 启动后**无需手动输入**即自动建团 + 召唤 6 成员 + 报就绪 + 回归协调者 | **`initialPrompt` 自动启动成立** | **CLOSE（PASS）** |
| 启动后**停在空会话**（未自动建团/召唤），需手动触发 | `initialPrompt` 未被自动提交 → 转 §2 降级验证 | 证伪 → 降级手动 |

## 2. 负向降级：手动执行等价验证

若 §1 正向不成立：

1. 在 `--agent dongmei-ma` 会话内，**手动**执行 `dongmei-ma.md`「§0 启动职责」/ `initialPrompt` 正文的步骤（建团 + 按序 spawn 6 teammate + 报就绪 + 回归协调者）。
2. 观察是否能正常建团 + 召唤 6 成员 + 报就绪。

**判定**：

| 观测结果 | 判定 |
| --- | --- |
| 手动执行后团队正常拉起、成员就绪、可接收查询 | **降级手动启动可用**——功能不依赖 `initialPrompt` 自动生效；README 标「手动启动」 |
| 手动执行仍拉不起团队 | 启动编排本身有缺陷（非 `initialPrompt` 问题），回修 `dongmei-ma.md` §0 |

## 3. 总判定与处置

- **§1 正向成立** → `initialPrompt` 自动启动坐实，命门 **CLOSE**：在测试报告 / README 把 TC-7.7 状态由「机制未坐实、待部署环境」改为 PASS，README 启动说明保留「自动」表述。
- **§1 证伪、§2 降级可用** → 自动机制在当前引擎不可得，但**功能等价可用**：README 启动说明改为「若 `initialPrompt` 不生效则手动执行 dongmei-ma.md §0 启动职责步骤」，`dongmei-ma.md` 诚实声明保留。**不得宣称自动已生效。**
- 无论哪个分支，**三道防线 / 独占边界不受影响**：dongmei-ma 不持任何源类 MCP、`TeamCreate`/`Agent` 非源类工具且仅用于召唤、不绕链路、独占归属不变。

## 附：一句话执行清单（TC-7.7）

1. `claude --agent dongmei-ma`，不输入 → 看是否自动建团+召唤 6 成员+回归协调者。
2. 自动成立 = PASS（CLOSE）；停在空会话 = 转手动。
3. 手动执行 §0 启动职责步骤 → 能拉起团队 = 降级可用。
4. 据实记录，勿写「一键自动已坐实/已生效」。
