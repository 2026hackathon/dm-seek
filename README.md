# dm-seek（马冬梅计划）

一套**可导入、开箱即用的 Claude Code 成品 team**——面向研发全角色的「代码现实 × 需求演进」追溯系统。用户一句自然语言疑问，team 自动完成 KB 线索 → 代码定位解读 → Git 时间线+抽工单号 → Jira 业务原因 → 综合 → 证据校验+置信度，交付带出处的演变报告，并沉淀回知识库。**以代码为唯一事实基准。**

引擎 = Claude Code（直连 Anthropic API，仅 Claude）；**非自建框架**。跨 Windows / macOS。详见 `docs/马冬梅计划-PRD.md`（v0.4）。

## 团队角色（首版 7 agent）

| agent | 职责 | 信息源 |
| --- | --- | --- |
| `dongmei-ma` | 编排、用户接口、驱动校验返工循环、默认中文交付 | 不直连信息源 |
| `kb-keeper` | 唯一 KB 读写口（Obsidian + Knowlery `/ask` `/cook`） | 知识库 |
| `code-analyst` | core-ng 代码定位+解读、repo+模块映射、KB 未命中源码兜底 | 代码内容（本地 / 远端经 repo-tracer） |
| `repo-tracer` | Git/GitHub 网关、独占 GitHub MCP、多仓路由、时间线+抽工单号 | 本地 Git / 多个 GitHub MCP 实例 |
| `jira-tracer` | 取工单业务原因与因果脉络（Jira MCP，只读） | Jira MCP |
| `synthesizer` | 综合 code+git+jira → 结论（9 类场景，分析方法沉淀为 skill） | 上游三源产物 |
| `evidence-verifier` | 出处校验 + 置信度（高/中/低）+ 不足触发发散返工 | 上游全部产物 |

> `design-tracer`（Figma 设计追溯）为二期。

## 目录结构

```
dm-seek/
├─ .claude/
│  ├─ agents/            7 个首版 agent 定义（本骨架已建）
│  │   ├─ dongmei-ma.md
│  │   ├─ kb-keeper.md
│  │   ├─ code-analyst.md
│  │   ├─ repo-tracer.md
│  │   ├─ jira-tracer.md
│  │   ├─ synthesizer.md
│  │   └─ evidence-verifier.md
│  └─ skills/            项目级 skills（路径 B：teammate 从此加载，非 frontmatter）
│      └─ README.md      skills 布局与计划（具体 skill 由实现任务填充）
├─ .mcp.json             共享 MCP 配置（GitHub 多仓 + Jira，凭据全 ${VAR} 占位）
├─ docs/                 PRD + 设计定稿 + 模板
│   ├─ 马冬梅计划-PRD.md
│   ├─ design-agent-io-schema.md          agent 间 I/O 契约 + 编排返工循环
│   ├─ design-core-ng-recognition.md      core-ng 识别规则（实地核验定稿）
│   ├─ design-source-switching-routing.md 双源切换 + 多仓路由 + 过时判定
│   ├─ design-synthesis-and-verification.md 综合 + 校验方法论
│   ├─ design-mcp-config-shape.md         MCP 配置形态 + 独占机制（路径 B）
│   ├─ design-jira-mcp-toolmap.md         Jira MCP 工具/端点对照
│   ├─ design-kb-init-and-integration.md  KB 初始化 + 集成形态
│   └─ templates/                         配置占位模板
└─ README.md
```

## 导入与使用（开箱即用）

1. **放置配置包**：将本仓库作为项目根（或把 `.claude/`、`.mcp.json` 并入你的项目）。
2. **配置凭据（环境变量化，零明文）**：由引导/配置 skill（`setup-guide`，task #15）协助完成——探测本地仓库、生成 `${DMSEEK_*}` 变量清单、按平台输出设置命令。所有 token / 邮箱由你**手填到自己的环境变量**，配置文件中只出现 `${VAR}` 占位。
   - GitHub（每仓一 token）：`DMSEEK_GH_TOKEN_<REPO_SLUG_UPPER>`
   - Jira：`DMSEEK_JIRA_SITE_NAME` / `DMSEEK_JIRA_EMAIL` / `DMSEEK_JIRA_API_TOKEN`
   - 设完变量后**重启 Claude Code / 终端**，`${VAR}` 才能展开。
3. **多仓**：每个 git repo 对应 `.mcp.json` 里一个 `github-<repoSlug>` 实例（独立 token）；引导 skill 增量追加，并同步把对应 `mcp__github-<repoSlug>__*` 工具加入 `repo-tracer` 的 `tools` 白名单。
4. **提问**：向 `dongmei-ma` 提一句自然语言疑问，team 自动协作并交付带置信度的中文报告。

## 安全与独占声明（重要，诚实声明）

- **凭据零明文**：任何配置文件（`.mcp.json` / agent `.md` / settings）只允许 `${VAR}` 占位，绝不出现真实 token。凭据全在 OS 环境变量。请勿提交含真实 token 的临时设置脚本。
- **源独占是策略级约束、非物理隔离**：本项目为 agent team（teammate 形态）。Claude Code 语义下，MCP 写在共享 `.mcp.json`，**会话层面对全 team 可见**；「GitHub MCP 独占 repo-tracer、Jira MCP 独占 jira-tracer、其他 agent 不直连源」靠**各 agent 的 `tools` 白名单**实现（白名单对 teammate 生效）——即只有被授予对应 `mcp__` 工具的 agent 能调用。这是**策略约束**，不是进程级物理隔离。
  - **per-agent 独占只有 `tools` 白名单这一层**：经核实，`deniedMcpServers`/`disabledMcpjsonServers` 等 MCP server 级策略均为会话级/组织级「一刀切」，**无 per-agent 粒度**——用它兜底会连合法的 repo-tracer/jira-tracer 一起禁掉，故本配置包**不挂 `deniedMcpServers` 作兜底**。部署方可选用 managed `allowedMcpServers` 锁定「只允许计划内 server」作 org 治理（防越界新增，不误伤授权 agent）。该承重假设的运行时验证与「证伪则升级」声明详见 `.claude/README.md`。
- **Jira 只读**：jira-tracer 仅授予 `mcp__jira__jira_get`，不授予写工单的工具。

## 状态

配置包**骨架**（task #8）已搭建：7 个 agent 定义、共享 MCP 占位、tools 白名单（独占落地）、skills 项目级布局、导入说明。各 agent 的 system prompt 实现细节、skills 内容由后续实现任务（#9–#15）填充。设计依据见 `docs/` 下各设计定稿。
