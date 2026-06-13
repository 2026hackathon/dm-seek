# dm-seek skills（项目级）

> **teammate 形态要点**：本项目是 agent team（teammate 形态）。Claude Code 官方语义下，teammate **不从** subagent frontmatter 的 `skills` 字段加载 skills，而是从**项目级 `.claude/skills/`**（与常规会话相同）加载。因此所有 dm-seek 的 skill **必须放在本目录**，不写进 agent frontmatter。

## skill 清单

| skill 目录 | 用途 | 主要使用者 |
| --- | --- | --- |
| `coreng-recognition/` | core-ng 识别规则（集中一处、可扩展的单一规则文件） | code-analyst |
| `synthesis-core/` | 9 类场景综合分析方法（六步骨架 + 场景库 method） | synthesizer |
| `kb-init/` | KB 初始化（入口点 + 调用链粗粒度建库） | kb-keeper / code-analyst |
| `setup-guide/` | 引导/配置（探测多仓、生成 `${VAR}` 清单、写 `.mcp.json` + tools 白名单、跨 Win/macOS） | 用户引导 |

> 所有 skill 入口文件统一为 `SKILL.md`。
