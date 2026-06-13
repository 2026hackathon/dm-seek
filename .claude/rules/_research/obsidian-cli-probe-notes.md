# 预研笔记 — obsidian CLI 实际调用形态实测

> **性质：预研笔记，非交付物。** 由 tools-dev 在等待 T7/T8 期间做的形态无关预研（tech-lead 授权范围：验证 obsidian CLI 调用形态，不写入交付物 `.claude/` 或 `skills/`）。供 T10 kb-keeper / T15 引导 skill 实现期参考，正式实现仍以 T8 骨架就位后为准。
> 实测环境：Windows，二进制 `D:\obsidian\Obsidian.com`（22KB CLI 启动器；GUI 是 `Obsidian.exe`）。`--help` 退出码 0、无 GUI 挂起。

---

## 1. 关键发现（影响 T10/T15 设计）

1. **CLI 真实命令面远比 PRD 假设的 `search/read/create/append` 丰富**，且这四个确实都在（验证了集成假设可行）：
   - `search query=<text> [path=<folder>] [limit=<n>] [total]`
   - `search:context query=<text> [path=] [limit=] [case] [format=text|json]` ← **检索带行上下文，更适合给线索**
   - `read file=<name> | path=<path>`
   - `create name=<name> [path=] [content=] [template=]`
   - `append file=|path= content=<text> [inline]`、`prepend ...`
   - 另有 `files`/`folders`/`tags`/`properties`/`property:set`/`property:read`/`move`/`rename`/`delete`/`links`/`backlinks` 等。

2. **`vault=<name>` 全局选项**：可指定目标 vault（`obsidian <command> vault=<name> ...`）。**多仓/多 vault 场景的关键**——若不同 repo 对应不同 vault，kb-keeper 据此切换（呼应 KB 设计 §2.4 repo 命名空间；具体是「一 vault 多 repo 命名空间」还是「多 vault」待真实环境定）。

3. **`format=text|json` 输出**：至少 `search:context`、`backlinks` 等支持 `format=json`。⇒ kb-keeper 应**优先用 `format=json`** 取结构化结果，便于解析喂给 code-analyst/synthesizer，避免脆弱的文本解析。

4. **⚠️ Knowlery `/ask` `/cook` 的真实调用路径可能是 `command`，而非 Skill 工具**：
   - CLI 有 `command id=<command-id>`（执行任意 Obsidian 命令）+ `commands filter=<prefix>`（列命令）。
   - Knowlery 是 Obsidian 插件 → 其 `/ask` `/cook` 极可能注册为 Obsidian 命令（id 形如 `knowlery:ask` / `knowlery:cook`），**可经 `obsidian command id=knowlery:xxx` 调用**。
   - 这与 T5 文档「kb-keeper 用 `Skill` 工具调 Knowlery」的假设**可能不同**——真实路径或许是「kb-keeper 用 `Bash` 调 `obsidian command id=...`」。
   - **实现期可执行验证**：`obsidian commands filter=knowlery`（带超时）即可列出 Knowlery 注册的真实命令 ID，定稿调用方式。这关闭 T5 §7 开放点1（Knowlery 接口）的一大半。

5. **路径/文件解析约定**：`file=` 按名解析（类 wikilink），`path=` 为精确路径（`folder/note.md`）；含空格的值要引号；`content` 里 `\n` `\t` 转义。kb-keeper 写库拼参数时须遵守。

6. **dot-dir 限制复核**：记忆 [[obsidian-cli-invocation]] 记「读不了 dot-dir」。本次未专门复测该限制（避免改动 vault），但 KB 目录无 dot 前缀的硬约束（KB 设计 §3.2/§4）继续保留，安全。

---

## 2. 对 T10 kb-keeper 实现的预研建议（待 T8 骨架后落地）

- 调用封装：`obsidian <command> [vault=<v>] [format=json] <args>`，统一经 `${DMSEEK_OBSIDIAN_CLI}` 取二进制路径（跨平台），容错「命令未找到」（PATH 未刷新）。
- 读线索：优先 `search:context ... format=json`（带上下文 + 结构化）而非裸 `search`。
- 写库：`create`（新建条目骨架）+ `append`/`prepend`（增量）；按 KB 设计 §6 SCHEMA 组织 frontmatter（`property:set` 可设条目属性）。
- Knowlery：实现期先 `commands filter=knowlery` 探明命令 ID，再定 `command id=...` 调用；若 Knowlery 未注册命令，回退到 Skill 工具方案。
- **⚠️ kb-keeper 白名单待 T10 据 Knowlery 真实调用路径校准（tech-lead 标记，影响 T8/T10，不阻塞 T7）**：若 Knowlery /ask /cook 经 `obsidian command id=knowlery:xxx`（即经 obsidian CLI）调用，则 kb-keeper 的 tools 白名单**关键是 `Bash`（跑 obsidian CLI），`Skill` 工具未必必需**。core-dev 的 T8 骨架给 kb-keeper 的白名单（Read/Bash/Skill/SendMessage）是**初始态、非最终态**——T10 实现时一句 `obsidian commands filter=knowlery` 探明真实路径后，确认 `Skill` 是否保留并定稿。
- 多 vault：先 `vaults`（列已知 vault）+ `vault`（当前 vault 信息）探明环境，再决定 repo↔vault 映射。

## 3. 待实现期验证项（不在本预研范围）

- Knowlery 真实命令 ID 与 `/ask` `/cook` 的入参/出参格式（需有真实 Knowlery 的环境）。
- `read`/`search` 在大 vault 的性能与分页。
- macOS 下二进制名与调用形态（`.com` vs 无后缀）。
- dot-dir 限制的精确边界（哪些命令受限）。
