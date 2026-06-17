# 验证-OAuth双轨登录

> 测试报告 | 日期：2026-06-16 | 测试者：qa-engineer-2
>
> 验证对象：T1-T4 产出（`repo-tracer.md` / `setup-guide/SKILL.md` / `mcp-servers.shared.placeholder.jsonc` / `design-github-oauth-login.md`）

## 执行摘要

**静态验证全部通过（4 维度 / 12 检查点）**——3 实现产物与设计文档 v1.2 一致、安全铁律三红线全守、独占机制未被改动、回归零波及。OAuth live 端到端验证受限于 harness 环境，标注为「待部署环境验证」。

---

## S1. 静态一致性

### S1.1 setup-guide 流程 vs 设计 §8

| 检查点 | 设计要求 | 实现证据 | 判定 |
|--------|---------|---------|------|
| 环境探测（§0.0） | 浏览器可用性判断 + 4 分支推荐路径 | setup-guide L25-L44：两检测项（浏览器/GUI + /plugin list）+ 4 分支决策树 | PASS |
| OAuth 分支步骤（§0.1） | check plugin installed → /plugin install → /mcp Authenticate → verify | setup-guide L55-L78：4 步（检查 → 安装 → 授权 → 验证），每步有跳过出口 | PASS |
| PAT 分支步骤（§0.2） | create PAT → set env var (防历史泄漏) → config .mcp.json → verify | setup-guide L102-L168：4 步，含 token scope 最小权限引导 + env var 设置 + .mcp.json 占位 | PASS |
| PAT 分支前置 Plugin 冲突检测 | 检测 + 三选项提示（留用/卸载/忽略） | setup-guide L88-L100：`checkPluginConflict` 含三选项（A: 用 OAuth / B: 卸载 Plugin / C: 保留但 PAT 不生效） | PASS |
| 失败处理 | 每步含跳过出口，失败不回滚已完成步骤 | setup-guide L77-L79 (OAuth 跳过) + L166-L168 (PAT 跳过) + L59 (安装失败 → 切 PAT) | PASS |
| 决策树与设计 §3.2 一致 | 有浏览器→OAuth，无浏览器→PAT | setup-guide L40-L44 与设计 §3.2 决策树完全对应 | PASS |

### S1.2 MCP 模板 vs 设计 §4.1/§4.2

| 检查点 | 设计要求 | 实现证据 | 判定 |
|--------|---------|---------|------|
| OAuth 路径：无 .mcp.json 条目 | Plugin 自行注册，模板不写 server 条目 | 模板 L18-L25：注释明确「无需在此添加任何条目——Plugin 自行注册」 | PASS |
| PAT 路径：server 名 `github` | 与 OAuth 路径同一 server 名 | 模板 L33-L40：示例 `"github": { "url": "https://api.githubcopilot.com/mcp/" }` | PASS |
| PAT 路径：token 仅 `${VAR}` 占位 | `.mcp.json` 仅含环境变量引用，不写明文 | 模板 L39：`"Authorization": "Bearer ${DMSEEK_GH_TOKEN_<REPO_SLUG_UPPER>}"` | PASS |
| 四场景行为矩阵 | 设计 §4.2.1 矩阵 | 模板 L11-L13：描述 Plugin 优先 + 静默忽略行为，与矩阵场景 2 对应 | PASS |
| 跨平台 env var 设置 | 防终端历史泄漏 | 模板 L42-L47：Windows `Read-Host -MaskInput` + macOS `read -s` | PASS |

### S1.3 repo-tracer tools 白名单 vs 设计 §4.4.1（18 工具清单）

| 设计 §4.4.1 工具 | frontmatter (L4) | body §1 表格 | 判定 |
|------------------|-----------------|-------------|------|
| `mcp__github__get_file_contents` | 有 | 有 | PASS |
| `mcp__github__list_commits` | 有 | 有 | PASS |
| `mcp__github__get_commit` | 有 | 有 | PASS |
| `mcp__github__search_code` | 有 | 有 | PASS |
| `mcp__github__list_branches` | 有 | 有 | PASS |
| `mcp__github__search_repositories` | 有 | 有 | PASS |
| `mcp__github__search_issues` | 有 | 有 | PASS |
| `mcp__github__search_pull_requests` | 有 | 有 | PASS |
| `mcp__github__get_issue` | 有 | 有 | PASS |
| `mcp__github__list_issues` | 有 | 有 | PASS |
| `mcp__github__get_pull_request` | 有 | 有 | PASS |
| `mcp__github__list_pull_requests` | 有 | 有 | PASS |
| `mcp__github__get_pull_request_files` | 有 | 有 | PASS |
| `mcp__github__get_pull_request_status` | 有 | 有 | PASS |
| `mcp__github__get_pull_request_comments` | 有 | 有 | PASS |
| `mcp__github__get_pull_request_reviews` | 有 | 有 | PASS |
| `mcp__github__search_users` | 有 | 有 | PASS |
| `mcp__github__get_authenticated_user` | 有 | 有 | PASS |

**frontmatter 工具总数**：18 个 `mcp__github__*` + 3 个非 MCP 工具（Bash, Read, SendMessage）= 21 total。与设计 §4.4.1 清单完全一致，无增无减。

### S1.4 `gh` CLI 彻底移除

| 检查点 | 预期 | 实际 | 判定 |
|--------|------|------|------|
| setup-guide 不含 `gh` CLI 安装/检测/引导 | 0 处功能引用 | 仅 4 处说明性提及（L23/L51/L135/L175），均为"不依赖 gh CLI"的否定声明，无功能引用 | PASS |
| repo-tracer 不含 `gh` CLI | 0 处 | `grep "gh" repo-tracer.md` 零结果 | PASS |
| 设计文档不含 `gh` CLI 功能依赖 | v1.2 已声明移除 | 设计 L7/L9/L20 声明 v1.2 彻底移除，设计 §8.3 有完整移除说明 | PASS |

---

## S2. 安全铁律

### S2.1 防 PSReadLine / 终端历史泄漏

| 检查点 | 设计要求（设计 §5.2.5） | 实现证据 | 判定 |
|--------|----------------------|---------|------|
| Windows PAT 设置推荐 `Read-Host -MaskInput` | 交互式输入，不写 PSReadLine 历史 | setup-guide L119-L123：`$token = Read-Host -Prompt "请粘贴 GitHub PAT" -MaskInput` | PASS |
| macOS PAT 设置推荐 `read -s` | 禁止回显，不写 bash 历史 | setup-guide L128-L130：`read -s -p "请粘贴 GitHub PAT: " token` | PASS |
| 事后清理指导 | 若已执行含明文命令 → 提供清理方法 | setup-guide L135-L136：`Clear-History` + 手动编辑 `ConsoleHost_history.txt` | PASS |
| 模板文件含防泄漏命令 | 与 setup-guide 一致的防泄漏引导 | 模板 L42-L47：同样使用 `Read-Host -MaskInput` / `read -s` | PASS |

### S2.2 零明文 token

| 检查点 | 预期 | 实际 | 判定 |
|--------|------|------|------|
| MCP 模板无明文 token | `${VAR}` 占位，无 `ghp_`/`gho_` 等真实 token 前缀 | 仅含 `${DMSEEK_GH_TOKEN_<REPO_SLUG_UPPER>}` 占位（L39），无真实 token 字符串 | PASS |
| setup-guide 不含 token 明文 | skill 不接触、不存储 token | L15「skill 不接收明文」+ L118「skill 绝不接触 token 明文」明确声明 | PASS |
| PAT 引导中 skill 不接收 token | 用户在自己终端执行，skill 仅提供命令模板 | L118「用户在本地终端执行，skill 仅提供命令模板」 | PASS |

### S2.3 凭据存储路径

| 检查点 | OAuth 路径 | PAT 路径 | 判定 |
|--------|-----------|----------|------|
| 凭据存储 | Claude Code keychain（加密） | 操作系统环境变量 | PASS |
| .mcp.json 是否落明文 | 零（Plugin 自注册，不写此文件） | 零（仅 `${VAR}` 占位） | PASS |
| setup-guide 是否索要 token | 不索要（用户通过 `/mcp` UI 完成） | 不索要（用户在终端执行，skill 不接触） | PASS |

---

## S3. 回归检查

### S3.1 独占机制（声明层 + 白名单）

| 检查点 | 预期 | 实际 | 判定 |
|--------|------|------|------|
| repo-tracer L1 白名单仅含 `mcp__github__*` + Bash/Read/SendMessage | 只读子集 18 工具 | frontmatter L4 精确 18 个 `mcp__github__*` 只读工具，不含写工具 | PASS |
| repo-tracer 声明区块 | 含「职责范围 / 允许 MCP / 边界约束」三区块 | repo-tracer L88-L103：三区块完整 | PASS |
| 声明区块与白名单一致 | 声明写「仅 GitHub Plugin 只读子集」 | L91「仅 GitHub 官方 Plugin 的只读子集——`mcp__github__*`」 | PASS |
| 声明区块含"不调 `mcp__atlassian__*`" | 明确禁止跨域 | L92「不调 `mcp__atlassian__*`（归 jira-tracer）」 | PASS |

### S3.2 其他 agent 未被改动

| agent | tools 白名单 | 是否含 `mcp__github` | 判定 |
|-------|-------------|---------------------|------|
| dongmei-ma | Read, TeamCreate, Agent, TaskCreate, TaskGet, TaskList, TaskUpdate, SendMessage | 仅在边界约束中作为禁止项 | PASS |
| kb-keeper | Read, Bash, Skill, SendMessage | 仅在边界约束中作为禁止项 | PASS |
| code-analyst | Read, Grep, Glob, Bash, Skill, SendMessage | 0 处 | PASS |
| jira-tracer | Read, SendMessage, mcp__atlassian__search_issues, mcp__atlassian__get_issue | 仅在边界约束中作为禁止项 | PASS |
| synthesizer | Read, Skill, SendMessage | 仅在边界约束中作为禁止项 | PASS |
| evidence-verifier | Read, SendMessage | 仅在边界约束中作为禁止项 | PASS |

**结论：所有非 repo-tracer agent 的 tools 白名单不含任何 `mcp__github__*` 工具，独占边界未被破坏。**

### S3.3 Jira plugin 引导未被改动

| 检查点 | 预期 | 实际 | 判定 |
|--------|------|------|------|
| Atlassian Plugin 安装引导 | `/plugin install atlassian@claude-plugins-official` | setup-guide L187 | PASS |
| OAuth 认证引导 | `/mcp` → Atlassian → Authenticate → 浏览器授权 | setup-guide L191-L196 | PASS |
| 验证方式 | jira-tracer 自检确认 `mcp__atlassian__search_issues` 可用 | setup-guide L199 | PASS |
| 流程无 gh CLI 或无关步骤 | 仅 Jira Plugin 相关 | L184-L199 无冗余步骤 | PASS |

---

## S4. 诚实标注

### S4.1 已验证 vs 待部署环境验证

| 验证项 | 验证方式 | 状态 | 依据文件 |
|--------|---------|------|---------|
| 18 工具白名单与设计 §4.4.1 一致 | 静态对比（frontmatter + body 表格 vs 设计清单） | 静态验证通过 | repo-tracer.md L4 + L36-L56 + 设计 §4.4.1 |
| setup-guide OAuth/PAT 双轨与设计 §8 一致 | 静态对比（skill 步骤 vs 设计流程图） | 静态验证通过 | setup-guide/SKILL.md §0 + 设计 §8 |
| MCP 模板零明文 | 文本搜索（无 `ghp_`/`gho_` 匹配） | 静态验证通过 | mcp-servers.shared.placeholder.jsonc |
| 防终端历史泄漏命令存在 | 静态文本确认 | 静态验证通过 | setup-guide L119-L136 |
| Plugin 冲突检测 | 静态文本确认 | 静态验证通过 | setup-guide L88-L100 |
| 独占边界未被破坏 | 6 agent 全文搜索 `mcp__github` | 静态验证通过 | 见 §3.2 |
| 其他 agent/Jira 引导未被改动 | 全文对比 | 静态验证通过 | 见 §3.2/§3.3 |
| `gh` CLI 彻底移除 | 全文搜索 `gh` 命令引用 | 静态验证通过 | setup-guide L23/L51/L135/L175 仅为否定声明 |
| OAuth live 流程（`/mcp` Authenticate → 浏览器跳转 → token → 工具可用） | 需真实 Claude Code + 浏览器 + GitHub OAuth | **待部署环境验证** | 设计 §2.1 流程 |
| PAT live 流程（token → env var → .mcp.json → 工具可用） | 需真实 Claude Code + GitHub PAT + Copilot MCP | **待部署环境验证** | 设计 §4.2/§4.4.2 |
| PAT 路径下 18 工具实际可用性 | 需 PAT 路径 live 实测 | **待部署环境验证** | 设计 §4.4.3 / §9.3 待定项 |
| 四场景行为矩阵（设计 §4.2.1）live 行为 | 需在四种场景下分别实测 | **待部署环境验证** | 设计 §4.2.1 |

**关键区分（诚实声明）**：
- 「静态验证通过」= 文件内容（mtime/size/文本搜索/grep diff）已正面佐证一致性
- 「live 端到端坐实」= 在真实 Claude Code 环境下完成完整 OAuth/PAT 流程并确认工具可用
- 本次报告覆盖前者完全，后者受限于 harness 环境无真实 Claude Code CLI、无浏览器、无 GitHub OAuth 回调能力——标注为「待部署环境验证」，**不将机制佐证冒充为 live 坐实**。

---

## S5. 未测项

| 未测项 | 原因 | 完成条件 |
|--------|------|---------|
| macOS 跨平台 setup-guide 引导实测 | 仅有 Windows 环境，无 macOS | macOS 环境可用时补测 |
| OAuth 浏览器跳转 → token → 工具可用全流程 | harness 环境无浏览器 | 用户真实环境（桌面 Claude Code）验证 |
| PAT headless 流程（token → .mcp.json → Copilot MCP → 工具可用） | harness 环境无 PAT token | 用户真实环境（含有效 PAT）验证 |
| PAT 路径 18 工具 vs Copilot MCP 实际注册工具差异清单 | 需 PAT live 实测 | 用户真实 PAT 环境验证 |
| setup-guide skill 作为 skill 被调用时的实际行为 | harness 无 claude CLI 可调用 skill | 用户真实环境实测 |
| repo-tracer 自检（OAuth/local-only 分层）实际运行 | harness 无法 spawn repo-tracer | 用户真实环境实测 |
| design-mcp-config-shape.md 同步更新 | 非本测试范围（tools-dev 职责） | 设计 §5.3/§9.3 建议项 |

---

## 结论

**静态验证：4 维度 / 12 检查点，全部 PASS。**

- 3 实现产物与设计文档 v1.2 一致（setup-guide 双轨、MCP 模板、repo-tracer 18 工具白名单）
- 安全铁律三红线全守：防终端历史泄漏、零明文 token、PAT 引导中 skill 不接触 token
- 独占机制（声明层 + 白名单）未被破坏，其他 6 agent 定义零波及
- `gh` CLI 从功能路径彻底移除，仅保留否定声明注释
- Jira plugin 引导未被改动
- OAuth live 流程、PAT live 流程、PAT 路径工具差异清单诚实标注为「待部署环境验证」
