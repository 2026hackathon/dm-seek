#!/usr/bin/env bash
# dm-seek macOS 一键初始化脚本
# 兼容 macOS 12+，依赖 Homebrew
# 支持重复运行——已有配置会增量合并
set -o pipefail

# ── bash 版本守卫（macOS 自带 bash 3.2；本脚本用关联数组等 bash 4+ 特性）──
# 检测到低版本时自动 exec 到 Homebrew 安装的新 bash；找不到则提示安装后退出。
if [ -z "${BASH_VERSINFO:-}" ] || [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    for _newbash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        [ -x "$_newbash" ] && exec "$_newbash" "$0" "$@"
    done
    echo "错误：本脚本需要 bash 4+（macOS 自带的是 3.2.x）。" >&2
    echo "请先安装新版 bash：brew install bash，然后重新运行本脚本。" >&2
    exit 1
fi

# ── 颜色 ──
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; WHITE='\033[0;37m'; NC='\033[0m'
info()    { echo -e "${WHITE}$*${NC}"; }
success() { echo -e "${GREEN}$*${NC}"; }
warn()    { echo -e "${YELLOW}$*${NC}"; }
error()   { echo -e "${RED}$*${NC}"; }
banner()  { echo; printf '%*s\n' 60 | tr ' ' '='; echo -e "  ${CYAN}$*${NC}"; printf '%*s\n' 60 | tr ' ' '='; echo; }

# ── 根目录解析 ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ "$(basename "$SCRIPT_DIR")" == "scripts" ]]; then
    ROOT_DIR="$(dirname "$SCRIPT_DIR")"
else
    ROOT_DIR="$SCRIPT_DIR"
fi
ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"

echo -e "${CYAN}dm-seek macos-setup.sh 启动中...${NC}"
info "运行目录: $ROOT_DIR"

# ── CLI 参数解析 ──
AUTO_MODE=false; PHASE_ARG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--auto) AUTO_MODE=true; shift ;;
        -p|--phase) PHASE_ARG="$2"; shift 2 ;;
        -p*) PHASE_ARG="${1#-p}"; shift ;;
        *) shift ;;
    esac
done

# ── 工具函数 ──
command_exists() { command -v "$1" &>/dev/null; }

get_branch_choice() {
    local default_branch="${1:-main}"; local branches=()
    if [[ -n "${2:-}" ]] && [[ -d "$2" ]]; then
        mapfile -t branches < <(git -C "$2" ls-remote --heads origin 2>/dev/null | sed 's|.*refs/heads/||')
    fi
    if [[ ${#branches[@]} -eq 0 ]] && command_exists gh && [[ -n "${3:-}" ]] && [[ -n "${4:-}" ]]; then
        mapfile -t branches < <(gh api "repos/$3/$4/branches" --jq ".[].name" 2>/dev/null)
    fi
    if [[ ${#branches[@]} -gt 0 ]]; then
        info "    可用分支（默认: $default_branch）："
        for i in "${!branches[@]}"; do
            local mark=""; [[ "${branches[$i]}" == "$default_branch" ]] && mark=" [默认]"
            info "      [$((i+1))] ${branches[$i]}$mark"
        done
        read -rp "    选择分支编号（回车使用默认）: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            local idx=$((choice - 1))
            [[ $idx -ge 0 ]] && [[ $idx -lt ${#branches[@]} ]] && echo "${branches[$idx]}" && return
        fi
    fi
    echo "$default_branch"
}

# ── 状态检测 ──
get_init_status() {
    local git_found=false gh_found=false gh_auth_ok=false gh_mcp_ok=false
    local obsidian_found=false obsidian_path="" brew_avail=false
    local auth_mode="none" mcp_json_mode="" mcp_json_exists=false
    local repo_count=0 repo_local_count=0 repo_remote_count=0
    local kb_total=0 kb_done=0

    command_exists brew && brew_avail=true
    command_exists git && git_found=true
    if command_exists gh; then
        gh_found=true
        # PAT 模式下跳过 gh auth status（无需 OAuth，命令必然超时）
        local is_pat=false
        if [[ -f "$ROOT_DIR/.mcp.json" ]]; then
            python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); g=d.get("mcpServers",{}).get("github",{}); sys.exit(0 if g.get("type")=="http" else 1)' "$ROOT_DIR/.mcp.json" 2>/dev/null && is_pat=true
        fi
        if [[ "$is_pat" == "true" ]]; then
            : # PAT 模式，跳过 auth 检查
        else
            timeout 10 gh auth status &>/dev/null && gh_auth_ok=true
        fi
        gh extension list 2>/dev/null | grep -q "shuymn/gh-mcp" && gh_mcp_ok=true
    fi

    # Obsidian CLI 探测
    local obs_paths=("${DMSEEK_OBSIDIAN_CLI:-}" "$HOME/.local/bin/obsidian" \
        "/Applications/Obsidian.app/Contents/MacOS/Obsidian" "/usr/local/bin/obsidian")
    for p in "${obs_paths[@]}"; do
        if [[ -n "$p" ]] && [[ -x "$p" || -f "$p" ]]; then
            obsidian_found=true; obsidian_path="$p"; break
        fi
    done

    # 认证模式判定
    local mcp_path="$ROOT_DIR/.mcp.json"
    if [[ -f "$mcp_path" ]]; then
        mcp_json_exists=true
        local mcp_raw; mcp_raw="$(cat "$mcp_path" 2>/dev/null)"
        if [[ "$mcp_raw" == "{}" || "$mcp_raw" == '{"mcpServers":{}}' ]]; then
            mcp_json_mode="empty"
        elif echo "$mcp_raw" | grep -q '"command".*"gh"'; then
            mcp_json_mode="oauth"
        elif echo "$mcp_raw" | grep -q 'GITHUB_TOKEN'; then
            mcp_json_mode="pat"
        fi
    fi

    if [[ "$mcp_json_mode" != "empty" ]]; then
        auth_mode="$mcp_json_mode"
    elif $gh_found && $gh_auth_ok && $gh_mcp_ok; then
        auth_mode="oauth"
    elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth_mode="pat"
    fi

    # repos.json
    local repos_path="$ROOT_DIR/.claude/repos.json"
    local repos_json="{}"
    local enabled_repo_count=0; local disabled_repo_count=0
    if [[ -f "$repos_path" ]]; then
        repos_json="$(cat "$repos_path" 2>/dev/null)"
        local stats; stats=$(python3 -c "
import sys,json
d=json.load(sys.stdin)
repos=d.get('repos',{})
total=len(repos)
local_c=sum(1 for r in repos.values() if r.get('local') and r['local'].get('path'))
enabled=sum(1 for r in repos.values() if r.get('enable',True)!=False)
disabled=total-enabled
print(f'{total}|{local_c}|{enabled}|{disabled}')
" <<< "$repos_json" 2>/dev/null || echo "0|0|0|0")
        IFS='|' read -r repo_count repo_local_count enabled_repo_count disabled_repo_count <<< "$stats"
        repo_remote_count=$((repo_count - repo_local_count))
    fi

    # KB vault 检测
    local dm_kbs="$ROOT_DIR/dm-kbs"
    if [[ -d "$dm_kbs" ]]; then
        while IFS= read -r vault_dir; do
            local vname; vname="$(basename "$vault_dir")"
            if [[ "$vname" =~ ^(.+)_kb$ ]]; then
                local slug="${BASH_REMATCH[1]}"
                if echo "$repos_json" | python3 -c "
import sys,json
d=json.load(sys.stdin)
kb=d.get('repos',{}).get('$slug',{}).get('kb')
print(kb is not None)
" 2>/dev/null | grep -q True; then
                    kb_total=$((kb_total + 1)); kb_done=$((kb_done + 1))
                fi
            fi
        done < <(find "$dm_kbs" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
    fi

    python3 -c "
import json
print(json.dumps({
    'GitFound': $( [[ $git_found == true ]] && echo true || echo false ),
    'GhFound': $( [[ $gh_found == true ]] && echo true || echo false ),
    'GhAuthOk': $( [[ $gh_auth_ok == true ]] && echo true || echo false ),
    'GhMcpOk': $( [[ $gh_mcp_ok == true ]] && echo true || echo false ),
    'ObsidianFound': $( [[ $obsidian_found == true ]] && echo true || echo false ),
    'ObsidianPath': '$obsidian_path',
    'BrewAvailable': $( [[ $brew_avail == true ]] && echo true || echo false ),
    'AuthMode': '$auth_mode',
    'McpJsonMode': '$mcp_json_mode',
    'McpJsonExists': $( [[ $mcp_json_exists == true ]] && echo true || echo false ),
    'RepoCount': $repo_count,
    'RepoLocalCount': $repo_local_count,
    'RepoRemoteCount': $repo_remote_count,
    'EnabledRepoCount': $enabled_repo_count,
    'DisabledRepoCount': $disabled_repo_count,
    'KbVaultTotal': $kb_total,
    'KbVaultDone': $kb_done
}))
"
}

show_status() {
    local s="$1"
    val() { echo "$s" | python3 -c "import sys,json; print(json.load(sys.stdin)['$1'])" 2>/dev/null; }
    local git_ok gh_ok obs_ok auth mcp rc rlc rrc kbt kbd enc dc
    git_ok=$(val GitFound); gh_ok=$(val GhFound); obs_ok=$(val ObsidianFound)
    auth=$(val AuthMode); mcp=$(val McpJsonMode)
    rc=$(val RepoCount); rlc=$(val RepoLocalCount); rrc=$(val RepoRemoteCount)
    kbt=$(val KbVaultTotal); kbd=$(val KbVaultDone)
    enc=$(val EnabledRepoCount); dc=$(val DisabledRepoCount)

    banner "dm-seek 初始化状态"
    local gi="[MISS]"; [[ "$git_ok" == "True" ]] && gi="[OK]"
    local ghi="[MISS]"; [[ "$gh_ok" == "True" ]] && ghi="[OK]"
    local oi="[WARN]"; [[ "$obs_ok" == "True" ]] && oi="[OK]"
    info "  git:       $gi"
    info "  gh CLI:    $ghi"
    info "  Obsidian:  $oi"
    info "  GitHub:    ${auth^^}"
    # .mcp.json consistency check
    local mcp_str="$mcp"
    if [[ "$auth" != "none" ]] && [[ "$mcp" != "empty" ]] && [[ "$auth" != "$mcp" ]]; then
        mcp_str="$mcp [WARN: 与认证模式不一致]"
    fi
    info "  .mcp.json: $mcp_str"
    local repo_str="$rc 个仓库 ($rlc 有本地, $rrc 仅远端)"
    [[ "$dc" -gt 0 ]] && repo_str="$repo_str ($enc 启用, $dc 禁用)"
    info "  repos.json: $repo_str"
    info "  KB vault:   $kbd/$kbt 已初始化"
}

show_menu() {
    local s="$1"
    val() { echo "$s" | python3 -c "import sys,json; print(json.load(sys.stdin)['$1'])" 2>/dev/null; }
    local auth mcp rc kbd kbt
    auth=$(val AuthMode); mcp=$(val McpJsonMode)
    rc=$(val RepoCount); kbd=$(val KbVaultDone); kbt=$(val KbVaultTotal)
    echo
    info "  操作："
    info "    [1] 重新探测环境"
    info "    [2] 配置 GitHub 认证 (当前: ${auth^^})"
    info "    [3] 管理仓库配置 ($rc 个仓库)"
    info "    [4] 初始化 KB Vault ($kbd/$kbt)"
    info "    [5] 生成 .mcp.json (当前: $mcp)"
    info "    [6] 连通性自检"
    info "    [7] 检查仓库更新"
    info "    [8] 刷新依赖图"
    info "    [0] 退出"
    echo
    read -rp "  选择: " choice
    echo "$choice"
}

# ══════════════════════════════════════════════════════════════
# Phase 1: 环境探测
# ══════════════════════════════════════════════════════════════
phase1() {
    banner "Phase 1/6: 环境探测"
    info "[检测] Homebrew..."
    if command_exists brew; then success "  Homebrew 可用 ($(brew --version | head -1))"
    else warn "  Homebrew 未安装，将无法自动安装依赖"
    fi

    info "[检测] git..."
    if command_exists git; then success "  git $(git --version 2>/dev/null | sed 's/git version //')"
    else
        warn "  git 未安装"
        if command_exists brew; then brew install git && success "  git 安装完成"; fi
    fi

    info "[检测] GitHub CLI (gh)..."
    if command_exists gh; then success "  gh CLI $(gh --version 2>/dev/null | head -1)"
    elif command_exists brew; then brew install gh && success "  gh CLI 安装完成"
    else warn "  gh CLI 未找到"
    fi

    info "[检测] Obsidian CLI..."
    local obs_found=""
    for p in "${DMSEEK_OBSIDIAN_CLI:-}" "$HOME/.local/bin/obsidian" \
        "/Applications/Obsidian.app/Contents/MacOS/Obsidian" "/usr/local/bin/obsidian"; do
        if [[ -n "$p" ]] && [[ -x "$p" || -f "$p" ]]; then obs_found="$p"; success "  Obsidian CLI: $p"; break; fi
    done
    [[ -z "$obs_found" ]] && warn "  Obsidian CLI 未找到（KB 功能需手动配置）"
}

# ══════════════════════════════════════════════════════════════
# Phase 2: GitHub 认证
# ══════════════════════════════════════════════════════════════
phase2() {
    banner "Phase 2/6: GitHub 认证"
    local a_ok=false b_ok=false
    info "[路径 A] gh CLI + OAuth"
    if command_exists gh; then
        success "  gh CLI: $(command -v gh)"
        if timeout 10 gh auth status &>/dev/null; then
            success "  gh auth: 已认证"
            if gh extension list 2>/dev/null | grep -q "shuymn/gh-mcp"; then
                success "  gh-mcp: 已安装"; a_ok=true
            else warn "  gh-mcp: 未安装（gh extension install shuymn/gh-mcp）"; fi
        else warn "  gh auth: 未认证（gh auth login）"; fi
    else warn "  gh CLI: 未安装"; fi

    info "[路径 B] PAT"
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then success "  GITHUB_TOKEN: 已设置"; b_ok=true
    else warn "  GITHUB_TOKEN: 未设置"; fi

    echo
    $a_ok && success "  [A] OAuth — 就绪" || warn "  [A] OAuth — 未就绪"
    $b_ok && success "  [B] PAT — 就绪" || warn "  [B] PAT — 未就绪"

    local mode="none"
    $a_ok && mode="oauth"
    [[ "$mode" == "none" ]] && $b_ok && mode="pat"

    if [[ "$mode" != "none" ]]; then
        info ">> 当前使用路径 ${mode^^}"
        read -rp "  是否修改？[y/N]: " change
        if [[ "$change" =~ ^[Yy]$ ]]; then
            info "  [A] OAuth  [B] PAT"; read -rp "  选择: " pick
            [[ "$pick" =~ ^[Aa]$ ]] && $a_ok && mode="oauth"
            [[ "$pick" =~ ^[Bb]$ ]] && $b_ok && mode="pat"
        fi
    else
        warn "→ A/B 均未就绪，请先配置 GitHub 认证"
        echo; read -rsp "  或现在输入 PAT（回车退出）: " manual; echo
        if [[ -n "$manual" ]]; then
            mode="pat"
            export GITHUB_TOKEN="$manual"
            # 写入当前 shell profile
            local rc_file="$HOME/.zshrc"
            [[ "$SHELL" != *zsh* ]] && rc_file="$HOME/.bash_profile"
            # 使用 macOS Keychain 存储 PAT，避免明文写入 shell profile
            if security add-generic-password -a "$USER" -s "dmseek_github_pat" -w "$manual" -U 2>/dev/null; then
                success "  GITHUB_TOKEN 已存入 Keychain（dmseek_github_pat）"
                local kc_line='export GITHUB_TOKEN=$(security find-generic-password -a "$USER" -s dmseek_github_pat -w 2>/dev/null)'
                grep -qF "$kc_line" "$rc_file" 2>/dev/null || echo "$kc_line" >> "$rc_file"
            else
                # Keychain 不可用时回退明文（chmod 600 保护 + %q 安全转义 + grep 去重）
                local pat_line; pat_line="$(printf 'export GITHUB_TOKEN=%q' "$manual")"
                grep -qF "$pat_line" "$rc_file" 2>/dev/null || echo "$pat_line" >> "$rc_file"
                chmod 600 "$rc_file" 2>/dev/null
                warn "  GITHUB_TOKEN 已写入 $rc_file（Keychain 不可用，已设 chmod 600）"
            fi
            warn "  注意：需新终端窗口使环境变量生效"
        fi
    fi
    echo "AUTH_MODE=$mode"
}

# ══════════════════════════════════════════════════════════════
# 自动扫描 dm-repos / dm-kbs
# ══════════════════════════════════════════════════════════════
auto_scan() {
    local repos_path="$ROOT_DIR/.claude/repos.json"
    local changed=false
    declare -A repos

    if [[ -f "$repos_path" ]]; then
        while IFS='|' read -r slug local_p owner repo branch kb_v kb_p; do
            IFS= read -r entry_json
            [[ -z "$slug" ]] && continue
            [[ -n "$local_p" ]] && repos["${slug}_local"]="$local_p"
            repos["${slug}_owner"]="$owner"; repos["${slug}_repo"]="$repo"
            repos["${slug}_branch"]="$branch"
            repos["${slug}_kb_vault"]="$kb_v"; repos["${slug}_kb_path"]="$kb_p"
            [[ -n "$entry_json" ]] && repos["${slug}_entry"]="$entry_json"
            repos["_slugs"]="${repos[_slugs]:+${repos[_slugs]} }$slug"
        done < <(python3 -c "
import json
d=json.load(open('$repos_path'))
for slug, r in d.get('repos',{}).items():
    lp = r.get('local',{}).get('path','') if r.get('local') else ''
    rm = r.get('remote',{})
    kb = r.get('kb',{})
    print(f'{slug}|{lp}|{rm.get(\"owner\",\"\")}|{rm.get(\"repo\",\"\")}|{rm.get(\"branch\",\"main\")}|{kb.get(\"vault\",\"\")}|{kb.get(\"path\",\"\")}')
    print(json.dumps(r))
" 2>/dev/null)
    fi

    local dm_repos="$ROOT_DIR/dm-repos"
    if [[ -d "$dm_repos" ]]; then
        while IFS= read -r git_dir; do
            local repo_dir; repo_dir="$(dirname "$git_dir")"
            local slug; slug="$(basename "$repo_dir")"
            local resolved; resolved="$(cd "$repo_dir" 2>/dev/null && pwd)"
            local tracked=false
            for s in ${repos[_slugs]}; do
                [[ "${repos[${s}_local]}" == "$resolved" ]] && tracked=true && break
            done
            $tracked && continue

            local remote_url; remote_url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)"
            local branch; branch="$(git -C "$repo_dir" branch --show-current 2>/dev/null || echo main)"
            local owner=""; local repo_name="$slug"
            if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then
                owner="${BASH_REMATCH[1]}"; repo_name="${BASH_REMATCH[2]%.git}"
            fi
            repos["${slug}_local"]="$resolved"
            repos["${slug}_owner"]="$owner"; repos["${slug}_repo"]="$repo_name"
            repos["${slug}_branch"]="$branch"
            repos["_slugs"]="${repos[_slugs]:+${repos[_slugs]} }$slug"
            changed=true
            info "  [auto] $slug — 自动发现: $owner/$repo_name [$branch]"
        done < <(find "$dm_repos" -maxdepth 2 -name ".git" -type d 2>/dev/null)
    fi

    local dm_kbs="$ROOT_DIR/dm-kbs"
    if [[ -d "$dm_kbs" ]]; then
        while IFS= read -r vault_dir; do
            local vname; vname="$(basename "$vault_dir")"
            if [[ "$vname" =~ ^(.+)_kb$ ]]; then
                local slug="${BASH_REMATCH[1]}"
                if [[ -n "${repos[${slug}_owner]}" ]] && [[ -z "${repos[${slug}_kb_vault]}" ]]; then
                    repos["${slug}_kb_vault"]="$vname"
                    repos["${slug}_kb_path"]="dm-kbs/$vname"
                    changed=true
                    info "  [auto] $slug — 关联 KB vault: $vname"
                fi
            fi
        done < <(find "$dm_kbs" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
    fi

    if $changed; then
        local slugs=(${repos[_slugs]})
        mkdir -p "$(dirname "$repos_path")"
        for slug in "${slugs[@]}"; do
            local lp="${repos[${slug}_local]}"
            local ow="${repos[${slug}_owner]}"
            local rp="${repos[${slug}_repo]}"
            local br="${repos[${slug}_branch]}"
            local kv="${repos[${slug}_kb_vault]}"
            local kp="${repos[${slug}_kb_path]}"
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$slug" "${lp:-}" "$ow" "$rp" "${br:-main}" "${kv:-}" "${kp:-}"
        done | python3 -c "
import json, sys
repos_path = '$repos_path'
try:
    d = json.load(open(repos_path))
except:
    d = {}
repos = d.setdefault('repos', {})
for line in sys.stdin:
    parts = line.rstrip('\n').split('\t', 6)
    if len(parts) < 7:
        continue
    slug, lp, ow, rp, br, kv, kp = parts
    entry = repos.get(slug, {})
    if lp:
        entry['local'] = {'path': lp}
    else:
        entry.pop('local', None)
    rm = entry.setdefault('remote', {})
    rm['owner'] = ow
    rm['repo'] = rp
    rm['branch'] = br if br else 'main'
    if kv:
        entry['kb'] = {'vault': kv, 'path': kp}
    else:
        entry.pop('kb', None)
    repos[slug] = entry
json.dump(d, open(repos_path, 'w'), indent=2)
" 2>/dev/null
    fi
}

# ══════════════════════════════════════════════════════════════
# Phase 3: 仓库配置
# ══════════════════════════════════════════════════════════════
phase3() {
    banner "Phase 3/6: 仓库配置"
    local repos_path="$ROOT_DIR/.claude/repos.json"
    declare -A repos

    if [[ -f "$repos_path" ]]; then
        while IFS='|' read -r slug local_p owner repo branch kb_v kb_p; do
            IFS= read -r entry_json
            [[ -z "$slug" ]] && continue
            [[ -n "$local_p" ]] && repos["${slug}_local"]="$local_p"
            repos["${slug}_owner"]="$owner"; repos["${slug}_repo"]="$repo"
            repos["${slug}_branch"]="$branch"
            repos["${slug}_kb_vault"]="$kb_v"; repos["${slug}_kb_path"]="$kb_p"
            [[ -n "$entry_json" ]] && repos["${slug}_entry"]="$entry_json"
            repos["_slugs"]="${repos[_slugs]:+${repos[_slugs]} }$slug"
            info "  已加载: $slug — $owner/$repo [$branch]"
        done < <(python3 -c "
import json
d=json.load(open('$repos_path'))
for slug, r in d.get('repos',{}).items():
    lp = r.get('local',{}).get('path','') if r.get('local') else ''
    rm = r.get('remote',{})
    kb = r.get('kb',{})
    print(f'{slug}|{lp}|{rm.get(\"owner\",\"\")}|{rm.get(\"repo\",\"\")}|{rm.get(\"branch\",\"main\")}|{kb.get(\"vault\",\"\")}|{kb.get(\"path\",\"\")}')
    print(json.dumps(r))
" 2>/dev/null)
    fi

    echo; info "[A] 调整仓库分支"; info "[B] 扫描并加载仓库"; info "[回车] 保持现有配置"
    read -rp "选择操作: " choice

    if [[ "$choice" =~ ^[Aa]$ ]]; then
        local slugs=(${repos[_slugs]})
        for i in "${!slugs[@]}"; do
            local s="${slugs[$i]}"; local br="${repos[${s}_branch]:-main}"
            info "  [$((i+1))] $s — ${repos[${s}_owner]}/${repos[${s}_repo]} [$br]"
        done
        read -rp "选择仓库编号: " sel
        if [[ "$sel" =~ ^[0-9]+$ ]]; then
            local idx=$((sel - 1)); local slug="${slugs[$idx]}"
            local old_br="${repos[${slug}_branch]}"; local local_p="${repos[${slug}_local]}"
            local owner="${repos[${slug}_owner]}"; local repo="${repos[${slug}_repo]}"
            local new_br; new_br=$(get_branch_choice "$old_br" "$local_p" "$owner" "$repo")
            if [[ "$new_br" != "$old_br" ]]; then
                repos["${slug}_branch"]="$new_br"
                success "  $slug 分支已更新: $new_br"
                if [[ -n "$local_p" ]] && [[ -d "$local_p/.git" ]]; then
                    info "    切换本地仓库分支: $old_br -> $new_br ..."
                    git -C "$local_p" fetch origin "$new_br" 2>/dev/null
                    if git -C "$local_p" checkout "$new_br" 2>/dev/null; then
                        success "    已切换到 $new_br"
                    else warn "    checkout 失败（可能有未提交的本地改动）"; fi
                fi
            fi
        fi
    fi

    if [[ "$choice" =~ ^[Bb]$ ]]; then
        # 本地扫描
        read -rp "是否扫描本地目录查找 git 仓库？[y/N]: " want_scan
        if [[ "$want_scan" =~ ^[Yy]$ ]]; then
            local scan_dirs=("$HOME/dev" "$HOME/projects" "$HOME/Developer" "/opt/dev")
            for dir in "${scan_dirs[@]}"; do
                [[ ! -d "$dir" ]] && continue
                info "  扫描 $dir ..."
                while IFS= read -r git_dir; do
                    local repo_dir; repo_dir="$(dirname "$git_dir")"
                    local slug; slug="$(basename "$repo_dir")"
                    local remote_url; remote_url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)"
                    local branch; branch="$(git -C "$repo_dir" branch --show-current 2>/dev/null || echo main)"
                    if [[ -n "$remote_url" ]]; then
                        local owner=""; local repo_name="$slug"
                        if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then
                            owner="${BASH_REMATCH[1]}"; repo_name="${BASH_REMATCH[2]%.git}"
                        fi
                        if [[ -z "${repos[${slug}_owner]}" ]]; then
                            repos["${slug}_local"]="$repo_dir"
                            repos["${slug}_owner"]="$owner"; repos["${slug}_repo"]="$repo_name"
                            repos["${slug}_branch"]="$branch"
                            repos["_slugs"]="${repos[_slugs]:+${repos[_slugs]} }$slug"
                            success "    [auto] $slug — $owner/$repo_name [$branch]"
                        fi
                    fi
                done < <(find "$dir" -maxdepth 3 -name ".git" -type d 2>/dev/null)
            done
        fi

        # 手动添加
        read -rp "是否手动添加本地仓库？[y/N]: " want_manual
        while [[ "$want_manual" =~ ^[Yy]$ ]]; do
            read -rp "输入本地仓库路径（回车跳过）: " local_p
            [[ -z "$local_p" ]] && break
            if [[ ! -d "$local_p/.git" ]]; then warn "  不是 git 仓库"; continue; fi
            local slug; slug="$(basename "$local_p")"
            local remote_url; remote_url="$(git -C "$local_p" remote get-url origin 2>/dev/null || true)"
            local branch; branch="$(git -C "$local_p" branch --show-current 2>/dev/null || echo main)"
            local owner=""; local repo_name="$slug"
            if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then
                owner="${BASH_REMATCH[1]}"; repo_name="${BASH_REMATCH[2]%.git}"
            fi
            local chosen; chosen=$(get_branch_choice "$branch" "$local_p" "$owner" "$repo_name")
            repos["${slug}_local"]="$local_p"
            repos["${slug}_owner"]="$owner"; repos["${slug}_repo"]="$repo_name"
            repos["${slug}_branch"]="$chosen"
            repos["_slugs"]="${repos[_slugs]:+${repos[_slugs]} }$slug"
            success "  已添加: $slug ($owner/$repo_name) [$chosen]"
            read -rp "继续添加？[y/N]: " want_manual
        done

        # 远端浏览 & clone
    # 注：当前仅取第一页 15 条。使用 [S] 可输入搜索关键词缩小范围
        read -rp "是否从远端浏览并 Clone 仓库？[y/N]: " want_remote
        if [[ "$want_remote" =~ ^[Yy]$ ]] && command_exists gh && timeout 10 gh auth status &>/dev/null; then
            local dm_repos="$ROOT_DIR/dm-repos"; mkdir -p "$dm_repos"
            read -rp "  Org（回车=个人）: " org
            local search_q
            if [[ -n "$org" ]]; then search_q="org:$org"
            else search_q="user:$(gh api user -q '.login')"; fi
            while true; do
                echo; info "  搜索: $search_q"
                local results; results="$(gh api "search/repositories?q=$search_q&per_page=15&sort=updated" \
                    --jq '.items[] | "\(.full_name)|\(.description // "")|\(.default_branch // "main")"' 2>/dev/null)"
                [[ -z "$results" ]] && { warn "  无结果"; break; }
                local i=1
                while IFS='|' read -r full_name desc def_br; do
                    local desc_short="${desc:0:60}"; [[ ${#desc} -gt 60 ]] && desc_short="${desc_short}..."
                    info "    [$i] $full_name — $desc_short"
                    ((i++))
                done <<< "$results"
                echo; info "  [#] 编号 clone  [D] 完成"; read -rp "  > " cmd
                [[ "$cmd" =~ ^[Dd]$ ]] && break
                if [[ "$cmd" =~ ^[0-9]+$ ]]; then
                    local line; line="$(echo "$results" | sed -n "${cmd}p")"
                    local full_name; full_name="$(echo "$line" | cut -d'|' -f1)"
                    local def_br; def_br="$(echo "$line" | cut -d'|' -f3)"
                    local slug; slug="${full_name##*/}"; local owner; owner="${full_name%%/*}"
                    local clone_path="$dm_repos/$slug"
                    info "  Clone: $full_name -> dm-repos/$slug ..."
                    git clone --branch "$def_br" "https://github.com/$full_name.git" "$clone_path" --progress 2>&1 | tail -3
                    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
                        local chosen; chosen=$(get_branch_choice "$def_br" "$clone_path" "$owner" "$slug")
                        if [[ "$chosen" != "$def_br" ]]; then
                            git -C "$clone_path" fetch origin "$chosen" 2>/dev/null
                            git -C "$clone_path" checkout "$chosen" 2>/dev/null
                        fi
                        repos["${slug}_local"]="$clone_path"
                        repos["${slug}_owner"]="$owner"; repos["${slug}_repo"]="$slug"
                        repos["${slug}_branch"]="$chosen"
                        repos["_slugs"]="${repos[_slugs]:+${repos[_slugs]} }$slug"
                        success "    $slug clone 完成 [$chosen]"
                    else warn "    $slug clone 失败"; fi
                fi
            done
        fi
    fi

    if [[ "$choice" =~ ^[Cc]$ ]]; then
        local slugs=(${repos[_slugs]})
        if [[ ${#slugs[@]} -eq 0 ]]; then
            warn "  无已配置仓库"
        else
            while true; do
                echo; info "  仓库启用/禁用状态："
                local repo_status
                repo_status=$(python3 -c "
import json
d = json.load(open('$repos_path'))
for slug, r in d.get('repos', {}).items():
    en = r.get('enable', True)
    print(f'{slug}|{str(en).lower()}')
" 2>/dev/null)
                for i in "${!slugs[@]}"; do
                    local s="${slugs[$i]}"
                    local enable_val
                    enable_val=$(echo "$repo_status" | grep "^${s}|" | cut -d'|' -f2 || echo "true")
                    local st; local color
                    [[ "$enable_val" == "true" ]] && st="✓ 启用" || st="✗ 禁用"
                    info "    [$((i+1))] $s — $st"
                done
                info "    [A] 全部启用  [D] 全部禁用  [回车] 返回"
                read -rp "  选择（单号/逗号分隔多号/A/D/回车）: " sel
                if [[ -z "$sel" ]]; then break; fi
                if [[ "$sel" =~ ^[Aa]$ ]]; then
                    python3 -c "
import json
d = json.load(open('$repos_path'))
for s in d.get('repos', {}):
    d['repos'][s]['enable'] = True
json.dump(d, open('$repos_path', 'w'), indent=2)
"
                    success "  已全部启用"
                elif [[ "$sel" =~ ^[Dd]$ ]]; then
                    python3 -c "
import json
d = json.load(open('$repos_path'))
for s in d.get('repos', {}):
    d['repos'][s]['enable'] = False
json.dump(d, open('$repos_path', 'w'), indent=2)
"
                    success "  已全部禁用"
                else
                    IFS=',' read -ra nums <<< "$sel"
                    for n in "${nums[@]}"; do
                        n=$(echo "$n" | xargs)  # trim
                        if [[ "$n" =~ ^[0-9]+$ ]]; then
                            local idx=$((n - 1))
                            if [[ $idx -ge 0 ]] && [[ $idx -lt ${#slugs[@]} ]]; then
                                local slug="${slugs[$idx]}"
                                local cur_enable
                                cur_enable=$(echo "$repo_status" | grep "^${slug}|" | cut -d'|' -f2 || echo "true")
                                local new_bool
                                [[ "$cur_enable" == "true" ]] && new_bool=False || new_bool=True
                                python3 -c "
import json
d = json.load(open('$repos_path'))
if '$slug' in d.get('repos', {}):
    d['repos']['$slug']['enable'] = $new_bool
json.dump(d, open('$repos_path', 'w'), indent=2)
"
                                local st
                                [[ "$new_bool" == "True" ]] && st="启用" || st="禁用"
                                success "    $slug → $st"
                            fi
                        fi
                    done
                fi
            done
        fi
    fi

    # 写回 repos.json（python3 merge：读现有JSON，保留所有顶层键和未知字段）
    local slugs=(${repos[_slugs]})
    if [[ ${#slugs[@]} -gt 0 ]]; then
        mkdir -p "$(dirname "$repos_path")"
        for slug in "${slugs[@]}"; do
            local lp="${repos[${slug}_local]}"; local ow="${repos[${slug}_owner]}"
            local rp="${repos[${slug}_repo]}"; local br="${repos[${slug}_branch]}"
            local kv="${repos[${slug}_kb_vault]}"; local kp="${repos[${slug}_kb_path]}"
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$slug" "${lp:-}" "$ow" "$rp" "${br:-main}" "${kv:-}" "${kp:-}"
        done | python3 -c "
import json, sys
repos_path = '$repos_path'
try:
    d = json.load(open(repos_path))
except:
    d = {}
repos = d.setdefault('repos', {})
for line in sys.stdin:
    parts = line.rstrip('\n').split('\t', 6)
    if len(parts) < 7:
        continue
    slug, lp, ow, rp, br, kv, kp = parts
    entry = repos.get(slug, {})
    if lp:
        entry['local'] = {'path': lp}
    else:
        entry.pop('local', None)
    rm = entry.setdefault('remote', {})
    rm['owner'] = ow
    rm['repo'] = rp
    rm['branch'] = br if br else 'main'
    if kv:
        entry['kb'] = {'vault': kv, 'path': kp}
    else:
        entry.pop('kb', None)
    repos[slug] = entry
json.dump(d, open(repos_path, 'w'), indent=2)
" 2>/dev/null
        success "repos.json 已写入（${#slugs[@]} 个仓库）"
    fi
}

# ══════════════════════════════════════════════════════════════
# Phase 4: KB Vault 初始化
# ══════════════════════════════════════════════════════════════
phase4() {
    banner "Phase 4/6: KB Vault 初始化"
    local repos_path="$ROOT_DIR/.claude/repos.json"
    [[ ! -f "$repos_path" ]] && { warn "  repos.json 不存在，跳过"; return; }
    local kb_dir="$ROOT_DIR/dm-kbs"; mkdir -p "$kb_dir"
    local created=()

    local slugs; slugs=$(python3 -c "
import json
d=json.load(open('$repos_path'))
print(' '.join(d.get('repos',{}).keys()))
" 2>/dev/null)

    # Obsidian 配置注册
    local obsidian_config="$HOME/Library/Application Support/obsidian/obsidian.json"
    local obsidian_avail=false; [[ -f "$obsidian_config" ]] && obsidian_avail=true
    local registered=0

    for slug in $slugs; do
        local vault_path="$kb_dir/${slug}_kb"
        [[ -f "$vault_path/.dmseek-init" ]] && continue
        mkdir -p "$vault_path/.obsidian"
        echo '{}' > "$vault_path/.obsidian/app.json"
        echo "macos-setup.sh $(date '+%Y-%m-%d %H:%M:%S')" > "$vault_path/.dmseek-init"
        created+=("$slug")
        python3 -c "
import json
d=json.load(open('$repos_path'))
if '$slug' in d.get('repos',{}):
    d['repos']['$slug']['kb'] = {'vault': '${slug}_kb', 'path': 'dm-kbs/${slug}_kb'}
json.dump(d, open('$repos_path','w'), indent=2)
" 2>/dev/null

        # 注册到 Obsidian 配置
        if $obsidian_avail; then
            python3 -c "
import json, uuid, time
cfg_path = '$obsidian_config'
cfg = json.load(open(cfg_path))
vaults = cfg.setdefault('vaults', {})
vault_path = '$vault_path'
already = any(v.get('path') == vault_path for v in vaults.values() if isinstance(v, dict))
if not already:
    vid = uuid.uuid4().hex[:16]
    vaults[vid] = {'path': vault_path, 'ts': int(time.time() * 1000), 'open': False}
    json.dump(cfg, open(cfg_path, 'w'), indent=2)
    print('registered')
" 2>/dev/null && registered=$((registered + 1))
        fi
    done

    if [[ ${#created[@]} -gt 0 ]]; then
        success "  已创建 vault: ${created[*]}"
        $obsidian_avail && [[ $registered -gt 0 ]] && success "  已注册 $registered 个 vault 到 Obsidian"
        info "  ┌─────────────────────────────────────────────────────┐"
        info "  │  下一步: 运行 KB-init 生成概念索引                    │"
        info "  │  /kb-init scope=all                                 │"
        info "  └─────────────────────────────────────────────────────┘"
    else info "  所有 vault 已存在，跳过"; fi
    echo
}

# ══════════════════════════════════════════════════════════════
# Phase 5: 配置生成
# ══════════════════════════════════════════════════════════════
phase5() {
    local auth_mode="${1:-none}"
    banner "Phase 5/6: 配置生成"
    if [[ "$auth_mode" == "none" ]]; then
        warn ".mcp.json 无法生成：GitHub 认证未配置"; return
    fi
    local mcp_path="$ROOT_DIR/.mcp.json"
    [[ -f "$mcp_path" ]] && info ".mcp.json 已存在，将增量合并 github + atlassian 配置（保留其它 MCP server）"
    # python3 读旧 JSON、仅 merge mcpServers.github（保留用户其它 server）；凭据 ${GITHUB_TOKEN} 环境变量化
    GITHUB_AUTH_MODE="$auth_mode" python3 - "$mcp_path" << 'PYEOF'
import json, os, sys
path = sys.argv[1]
mode = os.environ.get("GITHUB_AUTH_MODE", "none")
try:
    with open(path) as f:
        cfg = json.load(f)
    if not isinstance(cfg, dict):
        cfg = {}
except Exception:
    cfg = {}
servers = cfg.get("mcpServers")
if not isinstance(servers, dict):
    servers = {}
if mode == "oauth":
    servers["github"] = {"command": "gh", "args": ["mcp"], "env": {"GITHUB_READ_ONLY": "1"}}
else:
    servers["github"] = {
        "type": "http",
        "url": "https://api.githubcopilot.com/mcp",
        "headers": {"Authorization": "Bearer ${GITHUB_TOKEN}", "X-MCP-Readonly": "true"},
    }
# Atlassian/Jira：项目级 .mcp.json，Streamable HTTP；server 名固定 plugin_atlassian_atlassian（工具名 mcp__plugin_atlassian_atlassian__*）
servers["plugin_atlassian_atlassian"] = {"type": "http", "url": "https://mcp.atlassian.com/v1/mcp"}
cfg["mcpServers"] = servers
with open(path, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
PYEOF
    if [[ $? -ne 0 ]]; then
        error ".mcp.json 生成失败（python3 合并出错）"; return 1
    fi
    success ".mcp.json 已生成（github=$auth_mode 模式 + atlassian HTTP，增量合并）"

    # settings.json — 禁用 atlassian plugin（避免与 .mcp.json 同名 server 命名空间冲突）
    local settings_path="$ROOT_DIR/.claude/settings.json"
    if [[ -f "$settings_path" ]]; then
        python3 -c "
import json
with open('$settings_path') as f: s = json.load(f)
s.setdefault('enabledPlugins', {})['atlassian@claude-plugins-official'] = False
with open('$settings_path', 'w') as f: json.dump(s, f, indent=2)
" 2>/dev/null && success "settings.json 已更新（已禁用 atlassian plugin，改用 .mcp.json 远程 server）" || warn "settings.json 更新失败"
    else
        cat > "$settings_path" << 'SETTINGSEOF'
{
  "enabledPlugins": { "atlassian@claude-plugins-official": false }
}
SETTINGSEOF
        success "settings.json 已创建（atlassian 改用 .mcp.json 远程 server）"
    fi
    echo
}

# ══════════════════════════════════════════════════════════════
# Phase 6: 连通性自检
# ══════════════════════════════════════════════════════════════
phase6() {
    banner "Phase 6/6: 连通性自检"
    info "[GitHub]"
    if command_exists gh && timeout 10 gh auth status &>/dev/null; then
        success "  gh 认证状态: OK"
    else warn "  PAT 模式: 请重启 Claude Code 后运行 /mcp 确认 github server 已连接"; fi

    info "[Jira]"
    local jira_ok=false
    local mcp_path="$ROOT_DIR/.mcp.json"
    local settings_path="$ROOT_DIR/.claude/settings.json"
    if [[ -f "$mcp_path" ]]; then
        python3 -c "import json; d=json.load(open('$mcp_path')); exit(0 if d.get('mcpServers',{}).get('plugin_atlassian_atlassian') else 1)" 2>/dev/null && jira_ok=true
    fi
    # 提醒：plugin 仍启用会与 .mcp.json 同名 server 冲突
    if [[ -f "$settings_path" ]]; then
        python3 -c "import json; s=json.load(open('$settings_path')); exit(0 if s.get('enabledPlugins',{}).get('atlassian@claude-plugins-official') is True else 1)" 2>/dev/null && \
            warn "  [WARN] atlassian plugin 仍启用——会与 .mcp.json server 命名空间冲突，请运行 [5] 重新生成以禁用"
    fi
    if $jira_ok; then success "  Atlassian MCP 已配置（.mcp.json，Streamable HTTP）"
    else warn "  Atlassian MCP 未配置，请运行 [5] 生成配置"; fi
    info "  首次使用需认证：/mcp → plugin_atlassian_atlassian → Authenticate → 浏览器 OAuth"

    info "[Obsidian KB]"
    local obs_found=""
    for p in "${DMSEEK_OBSIDIAN_CLI:-}" "$HOME/.local/bin/obsidian" \
        "/Applications/Obsidian.app/Contents/MacOS/Obsidian" "/usr/local/bin/obsidian"; do
        if [[ -n "$p" ]] && [[ -x "$p" || -f "$p" ]]; then obs_found="$p"; break; fi
    done
    if [[ -n "$obs_found" ]]; then
        success "  Obsidian CLI: $obs_found"
        local rc_file="$HOME/.zshrc"
        [[ "$SHELL" != *zsh* ]] && rc_file="$HOME/.bash_profile"
        grep -q "DMSEEK_OBSIDIAN_CLI" "$rc_file" 2>/dev/null \
            || echo "export DMSEEK_OBSIDIAN_CLI=\"$obs_found\"" >> "$rc_file"
        success "  DMSEEK_OBSIDIAN_CLI 已写入 $rc_file"
    else warn "  Obsidian CLI 未找到（KB 功能需手动配置）"; fi

    banner "dm-seek 初始化完成"
    success "下一步: 在 Claude Code 中运行 /mcp 确认 github server 已连接，然后执行："
    success "  claude --agent dongmei-ma"; echo
}

# ══════════════════════════════════════════════════════════════
# Menu 7: 检查仓库更新
# ══════════════════════════════════════════════════════════════
check_updates() {
    banner "检查 dm-repos 仓库更新"
    local repos_path="$ROOT_DIR/.claude/repos.json"
    [[ ! -f "$repos_path" ]] && { warn "repos.json 不存在"; return; }

    local updatable=(); local current=(); local errors=()
    while IFS='|' read -r slug local_p branch; do
        [[ -z "$local_p" ]] && continue
        [[ ! -d "$local_p/.git" ]] && { errors+=("$slug — 本地仓库不可达"); continue; }
        git -C "$local_p" fetch origin "$branch" 2>/dev/null || true
        local behind; behind=$(git -C "$local_p" rev-list --count HEAD..origin/"$branch" 2>/dev/null || echo 0)
        if [[ "$behind" -gt 0 ]]; then
            updatable+=("$slug|$local_p|$branch|$behind")
        else current+=("$slug ($branch)"); fi
    done < <(python3 -c "
import json
d=json.load(open('$repos_path'))
for slug, r in d.get('repos',{}).items():
    lp = r.get('local',{}).get('path','') if r.get('local') else ''
    br = r.get('remote',{}).get('branch','main')
    print(f'{slug}|{lp}|{br}')
" 2>/dev/null)

    for e in "${errors[@]}"; do warn "  $e"; done
    for c in "${current[@]}"; do success "  已是最新: $c"; done

    if [[ ${#updatable[@]} -gt 0 ]]; then
        warn "  有待更新:"
        local i=1
        for u in "${updatable[@]}"; do
            IFS='|' read -r slug lp br behind <<< "$u"
            warn "    [$i] $slug [$br] — 落后 $behind 个提交"; ((i++))
        done
        echo; info "  [A] 一键全部更新  [#] 编号  [回车] 跳过"
        read -rp "  > " cmd
        local to_update=()
        if [[ "$cmd" =~ ^[Aa]$ ]]; then to_update=("${updatable[@]}")
        elif [[ "$cmd" =~ ^[0-9,]+$ ]]; then
            IFS=',' read -ra nums <<< "$cmd"
            for n in "${nums[@]}"; do
                local idx=$((n - 1))
                [[ $idx -ge 0 ]] && [[ $idx -lt ${#updatable[@]} ]] && to_update+=("${updatable[$idx]}")
            done
        fi
        for u in "${to_update[@]}"; do
            IFS='|' read -r slug lp br behind <<< "$u"
            info "  更新: $slug [$br] ..."
            if git -C "$lp" pull origin "$br" 2>&1; then success "    $slug 更新完成"
            else warn "    $slug 更新失败"; fi
        done
    elif [[ ${#current[@]} -eq 0 ]] && [[ ${#errors[@]} -gt 0 ]]; then
        warn "  所有仓库均不可达"
    else success "  所有仓库均已是最新"; fi
    echo
}

# ══════════════════════════════════════════════════════════════
# Phase 8: 刷新依赖图
# ══════════════════════════════════════════════════════════════
phase8() {
    banner "Phase 8: 刷新依赖图 (dependency-graph.json)"
    local repos_path="$ROOT_DIR/.claude/repos.json"
    local dep_path="$ROOT_DIR/.claude/dependency-graph.json"
    local dep_tmp="${dep_path}.tmp"
    local cache_path="${dep_path}.cache"

    [[ ! -f "$repos_path" ]] && { warn "repos.json 不存在"; return; }

    local repos_json; repos_json="$(cat "$repos_path" 2>/dev/null)"
    local total_repos; total_repos=$(python3 -c "import sys,json; print(len(json.load(sys.stdin).get('repos',{})))" <<< "$repos_json" 2>/dev/null || echo 0)
    [[ "$total_repos" -eq 0 ]] && { warn "repos.json 中无仓库"; return; }

    # 获取已启用仓库列表
    local enabled_repos; enabled_repos=$(python3 -c "
import json, sys
d=json.load(sys.stdin)
repos=d.get('repos',{})
enabled=[s for s,r in repos.items() if r.get('enable',True)!=False]
print(' '.join(enabled))
" <<< "$repos_json" 2>/dev/null)
    [[ -z "$enabled_repos" ]] && { warn "无已启用仓库"; return; }

    info "已启用仓库: $enabled_repos"

    # 加载 SHA 缓存
    local sha_cache="{}"
    local data_cache="{}"
    if [[ -f "$dep_path" ]]; then
        sha_cache=$(python3 -c "
import json
d=json.load(open('$dep_path'))
shas=d.get('repoHeadShas',{})
print(json.dumps({k:v for k,v in shas.items() if v}))
" 2>/dev/null || echo "{}")
    fi
    if [[ -f "$cache_path" ]]; then
        data_cache=$(cat "$cache_path" 2>/dev/null || echo "{}")
    fi

    # 逐仓库解析
    local parse_script; parse_script=$(python3 << PYEOF
import json, subprocess, os, sys

repos_path = "$repos_path"
data_cache = json.loads("""$data_cache""") if "$data_cache" != "{}" else {}
sha_cache = json.loads("""$sha_cache""") if "$sha_cache" != "{}" else {}

d = json.load(open(repos_path))
repos = d.get('repos', {})
enabled = [s for s,r in repos.items() if r.get('enable',True)!=False]

exports = {}
consumed = {}
new_data = {}
parsed = 0
cached = 0

for slug in enabled:
    r = repos[slug]
    lp = r.get('local', {}).get('path', '') if r.get('local') else ''
    sha = None
    if lp and os.path.isdir(os.path.join(lp, '.git')):
        try:
            sha = subprocess.check_output(['git', '-C', lp, 'rev-parse', 'HEAD'], stderr=subprocess.DEVNULL).decode().strip()
        except:
            pass

    # SHA 缓存检查
    cached_entry = data_cache.get(slug, {})
    if sha and cached_entry.get('sha') == sha:
        cached += 1
        sys.stderr.write(f'  {slug} -- SHA未变，复用缓存\n')
        aid = cached_entry.get('artifactId')
        if aid:
            exports[aid] = {'repo': slug, 'version': cached_entry.get('version')}
        deps = cached_entry.get('dependencies', [])
        if deps:
            consumed[slug] = deps
        new_data[slug] = cached_entry
        continue

    parsed += 1
    sys.stderr.write(f'  解析 {slug} ...\n')
    aid = None
    ver = None
    deps = []

    # publish.json (structure: { "modules": [{ "artifactId", "version" }] })
    pub_path = os.path.join(lp, 'publish.json') if lp else None
    if pub_path and os.path.isfile(pub_path):
        try:
            pub = json.load(open(pub_path))
            modules = pub.get('modules', [])
            if modules:
                for mod in modules:
                    ma = mod.get('artifactId')
                    if ma:
                        exports[ma] = {'repo': slug, 'version': mod.get('version', '0.0.0')}
                first = modules[0]
                aid = first.get('artifactId')
                ver = first.get('version', '0.0.0')
                sys.stderr.write(f'    publish.json -> {len(modules)} module(s), primary: {aid}:{ver}\n')
        except:
            sys.stderr.write(f'    publish.json 解析失败\n')

    # -- Generic version resolution --
    # Step 0: scan ALL .kt/.kts files for version constants
    #     (val | var | const val) <anyName> = "<version>"
    global_vars = {}
    if lp and os.path.isdir(lp):
        import re
        for root, dirs, files in os.walk(lp):
            dirs[:] = [d for d in dirs if 'build' not in d or d == 'buildSrc']
            for f in files:
                if f.endswith('.kt') or f.endswith('.kts'):
                    try:
                        with open(os.path.join(root, f)) as kf:
                            kcontent = kf.read()
                        for vm in re.finditer(r'(?:const\s+val|val|var)\s+(\w+)\s*=\s*"([0-9][0-9.]*)"', kcontent):
                            global_vars[vm.group(1)] = vm.group(2)
                    except:
                        pass

    # Step 1: recursive build.gradle.kts, match com.wonder:* deps
    if lp and os.path.isdir(lp):
        import re
        seen_deps = set()
        for root, dirs, files in os.walk(lp):
            dirs[:] = [d for d in dirs if d not in ('build', '.git')]
            for f in files:
                if f == 'build.gradle.kts':
                    try:
                        with open(os.path.join(root, f)) as gf:
                            content = gf.read()
                        for m in re.finditer(r'com\.wonder:([a-zA-Z0-9_-]+):(?:([0-9][0-9.]*)|\$\{([^}]+)\})', content):
                            da = m.group(1)
                            dv = None
                            if m.group(2):
                                dv = m.group(2)
                            elif m.group(3):
                                ref = m.group(3)
                                dv = global_vars.get(ref)
                                if not dv:
                                    dv = global_vars.get(ref.split('.')[-1])
                            if da == 'wonder-dependencies':
                                continue
                            if not dv:
                                dv = 'unknown'
                            key = f"{da}:{dv}"
                            if key not in seen_deps:
                                seen_deps.add(key)
                                deps.append({'artifact': da, 'version': dv, 'full': f'{da}:{dv}'})
                    except:
                        pass
        if deps:
            sys.stderr.write(f'    build.gradle.kts -> {len(deps)} deps (deduped)\n')

    new_data[slug] = {
        'sha': sha,
        'artifactId': aid,
        'version': ver,
        'dependencies': deps
    }

# 跨仓匹配
edges = []
unmatched = []
seen_edges = set()

for slug in enabled:
    for dep in consumed.get(slug, []):
        da = dep['artifact']
        dv = dep['version']
        export = exports.get(da)
        if export and export['repo'] != slug:
            ev = export['version']
            # version comparison (handle unknown)
            if dv == 'unknown' or ev == 'unknown':
                vm = 'unknown'
            else:
                def cmp_ver(a, b):
                    pa = [int(x) for x in a.split('.')]
                    pb = [int(x) for x in b.split('.')]
                    for i in range(max(len(pa), len(pb))):
                        va = pa[i] if i < len(pa) else 0
                        vb = pb[i] if i < len(pb) else 0
                        if va < vb: return -1
                        if va > vb: return 1
                    return 0
                vc = cmp_ver(dv, ev)
                vm = 'exact' if vc == 0 else ('behind' if vc < 0 else 'ahead')
            edge_key = f"{slug}|{export['repo']}|{da}"
            if edge_key not in seen_edges:
                seen_edges.add(edge_key)
                edges.append({
                    'fromRepo': slug,
                    'toRepo': export['repo'],
                    'viaArtifact': da,
                    'versionConsumed': dv,
                    'versionExported': ev,
                    'versionMatch': vm,
                    'relationship': 'api-contract',
                    'source': 'auto'
                })
                sys.stderr.write(f'  匹配: {slug} -> {export["repo"]} via {da} ({vm})\n')
        elif not export:
            # unmatched
            missing = None
            import re as re2
            mm = re2.match(r'^(.+)-service-interface$', da)
            if mm: missing = mm.group(1)
            else:
                mm = re2.match(r'^(.+)-client$', da)
                if mm: missing = mm.group(1)
                else:
                    mm = re2.match(r'^(.+)-api$', da)
                    if mm: missing = mm.group(1)
            unmatched.append({
                'repo': slug,
                'artifact': dep['full'],
                'likelyMissingRepo': missing,
                'likelyThirdParty': False
            })
            sys.stderr.write(f'  未匹配: {slug} -- {dep["full"]} (可能缺失: {missing})\n')

# 预计算 reverseEdges
rev = {}
for e in edges:
    tr = e['toRepo']
    rev.setdefault(tr, []).append({'fromRepo': e['fromRepo'], 'viaArtifact': e['viaArtifact']})

# DFS 循环检测
cycles = False
adj = {}
for e in edges:
    adj.setdefault(e['fromRepo'], []).append(e['toRepo'])

white = {s: True for s in enabled}
gray = {}
black = {}

def dfs(n):
    global cycles
    white.pop(n, None)
    gray[n] = True
    for nb in adj.get(n, []):
        if nb in gray:
            cycles = True
            return
        if nb in white:
            dfs(nb)
    gray.pop(n, None)
    black[n] = True

for n in enabled:
    if n in white:
        dfs(n)
        if cycles:
            break

# repoHeadShas
shas_out = {}
for slug in enabled:
    nd = new_data.get(slug, {})
    shas_out[slug] = nd.get('sha')

# 构建输出
result = {
    'schemaVersion': '1.0',
    'generatedAt': subprocess.check_output(['date', '-u', '+%Y-%m-%dT%H:%M:%SZ']).decode().strip(),
    'enabledRepos': enabled,
    'repoHeadShas': shas_out,
    'edges': edges,
    'reverseEdges': rev,
    'unmatched': unmatched,
    'cyclesDetected': cycles
}

# 原子写入
with open('$dep_tmp', 'w') as f:
    json.dump(result, f, indent=2, ensure_ascii=False)

if os.path.exists('$dep_path'):
    os.remove('$dep_path')
os.rename('$dep_tmp', '$dep_path')

# 写入数据缓存
with open('$cache_path', 'w') as f:
    json.dump(new_data, f, indent=2, ensure_ascii=False)

print(f"OK|{len(edges)}|{len(unmatched)}|{str(cycles).lower()}|{parsed}|{cached}")
PYEOF
)
    IFS='|' read -r status edge_count unmatched_count cycles_str parsed_count cached_count <<< "$parse_script"
    if [[ "$status" == "OK" ]]; then
        success "依赖图已写入: .claude/dependency-graph.json"
        info "  edges: $edge_count 条"
        info "  unmatched: $unmatched_count 条"
        info "  cyclesDetected: $cycles_str"
        info "  已解析: ${parsed_count:-0} | 缓存命中: ${cached_count:-0}"
    else
        warn "依赖图生成失败"
    fi
}

# ══════════════════════════════════════════════════════════════
# Main
# ══════════════════════════════════════════════════════════════
main() {
    echo
    printf '%*s\n' 60 | tr ' ' '═'
    echo -e "  ${CYAN}dm-seek（马冬梅计划）${NC}"
    echo -e "  ${CYAN}macOS 一键初始化脚本${NC}"
    printf '%*s\n' 60 | tr ' ' '═'
    echo

    # 检查 python3（macOS 自带）
    if ! command_exists python3; then
        error "需要 python3，请安装 Xcode Command Line Tools: xcode-select --install"
        exit 1
    fi

    auto_scan

    # CLI 参数：-a 全量执行，-p N 直接跳转
    if $AUTO_MODE; then
        info "全量执行模式：依次运行 Phase 1-6..."
        phase1; local mode_p2; mode_p2="$(phase2 | grep 'AUTH_MODE=' | cut -d'=' -f2)"
        phase3; phase4; phase5 "$mode_p2"; phase6
        exit 0
    fi
    if [[ -n "$PHASE_ARG" ]]; then
        case "$PHASE_ARG" in
            1) phase1 ;;
            2) local r2; r2="$(phase2 | grep 'AUTH_MODE=' | cut -d'=' -f2)"; [[ -n "$r2" && "$r2" != "none" ]] && phase5 "$r2" ;;
            3) phase3 ;;
            4) phase4 ;;
            5) phase5 "$(get_init_status | python3 -c "import sys,json; print(json.load(sys.stdin)['AuthMode'])")" ;;
            6) phase6 ;;
            7) check_updates ;;
            8) phase8 ;;
            *) error "无效 Phase: $PHASE_ARG（有效值: 1-8）" ;;
        esac
        exit 0
    fi

    while true; do
        local status; status="$(get_init_status)"
        show_status "$status"
        local choice; choice="$(show_menu "$status")"

        case "$choice" in
            1) phase1 ;;
            2)
                local auth_result; auth_result="$(phase2)"
                local auth_mode; auth_mode="$(echo "$auth_result" | grep 'AUTH_MODE=' | cut -d'=' -f2)"
                local prev_mode; prev_mode="$(echo "$status" | python3 -c "import sys,json; print(json.load(sys.stdin)['AuthMode'])")"
                if [[ "$auth_mode" != "none" ]] && [[ "$auth_mode" != "$prev_mode" ]]; then
                    info "认证模式已变更，自动更新 .mcp.json..."; phase5 "$auth_mode"
                fi
                ;;
            3) phase3 ;;
            4) phase4 ;;
            5) phase5 "$(echo "$status" | python3 -c "import sys,json; print(json.load(sys.stdin)['AuthMode'])")" ;;
            6) phase6 ;;
            7) check_updates ;;
            8) phase8 ;;
            0) info "退出。"; break ;;
            *) [[ -n "$choice" ]] && warn "无效选择: $choice" ;;
        esac
    done
}

main
