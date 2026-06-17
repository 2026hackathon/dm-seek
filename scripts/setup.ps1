<#
.SYNOPSIS
    dm-seek Windows 一键初始化脚本
.DESCRIPTION
    自动探测环境、引导 GitHub 认证、配置仓库、生成 .mcp.json 和 repos.json。
    兼容 Windows PowerShell 5.1+（Win 10+ 自带）。
    支持重复运行——已有配置会增量合并而非覆盖。
#>
#Requires -Version 5.1

$ErrorActionPreference = "Stop"
$script:RootDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $script:RootDir) { $script:RootDir = Get-Location }
$script:RootDir = (Resolve-Path $script:RootDir).Path

# ============================================================
# 工具函数
# ============================================================

function Write-Info($msg)    { Write-Host $msg -ForegroundColor White }
function Write-Success($msg) { Write-Host $msg -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host $msg -ForegroundColor Yellow }
function Write-ErrorMsg($msg){ Write-Host $msg -ForegroundColor Red }
function Write-Banner($msg)  { Write-Host ("`n" + "=" * 60) -ForegroundColor Cyan; Write-Host "  $msg" -ForegroundColor Cyan; Write-Host ("=" * 60 + "`n") -ForegroundColor Cyan }

function Test-Command($cmd) {
    $null = Get-Command $cmd -ErrorAction SilentlyContinue
    return $?
}

function Test-Winget {
    $result = $null
    try { $result = winget --version 2>$null } catch { }
    return ($null -ne $result)
}

function Install-WingetPackage($packageId, $displayName) {
    Write-Info "正在安装 $displayName ..."
    try {
        winget install --id $packageId --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "  $displayName 安装完成"
            return $true
        } else {
            Write-Warn "  winget 安装 $displayName 返回非零退出码，请检查"
            return $false
        }
    } catch {
        Write-Warn "  winget 安装失败: $_"
        return $false
    }
}

function Read-MaskedInput($prompt) {
    $secure = Read-Host -Prompt $prompt -AsSecureString
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

# ============================================================
# Phase 1: 环境探测
# ============================================================

function Invoke-Phase1 {
    Write-Banner "Phase 1/5: 环境探测"

    $env = @{
        GitFound = $false
        GhFound = $false
        GhPath = $null
        ObsidianPath = $null
        LocalRepos = @()
        WingetAvailable = $false
    }

    # --- winget ---
    Write-Info "[检测] winget（包管理器）..."
    $env.WingetAvailable = Test-Winget
    if ($env.WingetAvailable) {
        Write-Success "  winget 可用"
    } else {
        Write-Warn "  winget 不可用——将无法自动安装 git/gh CLI（需手动安装）"
    }

    # --- git（硬依赖，自动安装）---
    Write-Info "[检测] git..."
    if (Test-Command "git") {
        $gitVer = (git --version 2>$null) -replace "git version ", ""
        Write-Success "  git $gitVer"
        $env.GitFound = $true
    } else {
        Write-Warn "  git 未安装"
        if ($env.WingetAvailable) {
            Write-Info "  正在通过 winget 自动安装 Git..."
            if (Install-WingetPackage "Git.Git" "Git") {
                Write-Warn "  git 安装完成，但需重启终端使 PATH 生效。脚本将继续，但 git 命令可能不可用。"
                $env.GitFound = $true
            }
        } else {
            Write-ErrorMsg "  winget 不可用，请手动安装 git: https://git-scm.com/download/win"
            Write-ErrorMsg "  git 是 dm-seek 的必要依赖，安装后请重新运行本脚本。"
            exit 1
        }
    }

    # --- gh CLI ---
    Write-Info "[检测] GitHub CLI (gh)..."
    $ghPaths = @(
        "gh"
        "$env:ProgramFiles\GitHub CLI\gh.exe"
        "${env:ProgramFiles(x86)}\GitHub CLI\gh.exe"
        "$env:LOCALAPPDATA\GitHubCLI\gh.exe"
        "$env:USERPROFILE\scoop\shims\gh.exe"
    )
    $ghFound = $false
    foreach ($p in $ghPaths) {
        if (Test-Command $p) {
            $env.GhPath = $p
            $env.GhFound = $true
            $ghVer = (& $p --version 2>$null | Select-Object -First 1) -replace "gh version ", ""
            Write-Success "  gh CLI $ghVer ($p)"
            break
        }
    }
    if (-not $env.GhFound) {
        Write-Warn "  gh CLI 未找到（Phase 2 将提供安装选项）"
    }

    # --- obsidian CLI ---
    Write-Info "[检测] Obsidian CLI..."
    $obsPaths = @(
        "$env:DMSEEK_OBSIDIAN_CLI"
        "D:\obsidian\Obsidian.com"
        "$env:LOCALAPPDATA\obsidian\Obsidian.com"
        "$env:USERPROFILE\AppData\Local\obsidian\Obsidian.com"
    )
    foreach ($p in $obsPaths) {
        if ($p -and (Test-Path $p)) {
            $env.ObsidianPath = $p
            Write-Success "  Obsidian CLI: $p"
            break
        }
    }
    if (-not $env.ObsidianPath) {
        Write-Warn "  Obsidian CLI 未找到（不影响核心功能，KB 功能需手动配置）"
    }

    # --- 本地 git 仓库扫描 ---
    Write-Info "[扫描] 本地 git 仓库..."
    $scanDirs = @()
    Write-Info "  请输入要扫描的目录（多个用逗号分隔，直接回车跳过）："
    $userInput = Read-Host "  >"
    if ($userInput) {
        $scanDirs += ($userInput -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    # 追加常见开发目录
    $commonDirs = @(
        "$env:USERPROFILE\dev", "$env:USERPROFILE\projects",
        "D:\dev", "D:\dev_repository", "D:\projects",
        "C:\dev", "C:\projects"
    )
    foreach ($d in $commonDirs) {
        if ((Test-Path $d) -and ($scanDirs -notcontains $d)) {
            $scanDirs += $d
        }
    }
    foreach ($dir in $scanDirs) {
        if (-not (Test-Path $dir)) { continue }
        Write-Info "  扫描 $dir ..."
        $gitDirs = Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName ".git") }
        foreach ($gd in $gitDirs) {
            $remoteUrl = $null
            $branch = $null
            try {
                $remoteUrl = (git -C $gd.FullName remote get-url origin 2>$null)
                $branch = (git -C $gd.FullName branch --show-current 2>$null)
            } catch { }
            if ($remoteUrl) {
                $slug = [System.IO.Path]::GetFileName($gd.FullName)
                $ownerRepo = ""
                if ($remoteUrl -match "github\.com[:/](.+)/(.+?)(\.git)?$") {
                    $ownerRepo = "$($Matches[1])/$($Matches[2])"
                }
                $env.LocalRepos += @{
                    Path = $gd.FullName
                    Slug = $slug
                    RemoteUrl = $remoteUrl
                    OwnerRepo = $ownerRepo
                    Branch = if ($branch) { $branch } else { "main" }
                }
                Write-Success "    发现: $slug ($ownerRepo) [$branch]"
            }
        }
    }
    if ($env.LocalRepos.Count -eq 0) {
        Write-Warn "  未发现本地 git 仓库"
    } else {
        Write-Success "  共发现 $($env.LocalRepos.Count) 个本地仓库"
    }

    Write-Info ""
    return $env
}

# ============================================================
# Phase 2: GitHub 认证
# ============================================================

function Invoke-Phase2($env) {
    Write-Banner "Phase 2/5: GitHub 认证"

    $choice = $null

    if ($env.GhFound) {
        Write-Info "检测到 gh CLI 已安装。请选择认证方式："
        Write-Info "  [A] gh-mcp OAuth（推荐）——浏览器 OAuth 认证，零 PAT"
        Write-Info "  [B] PAT ——手动创建 Personal Access Token，适合 headless/无浏览器"
        while ($choice -notin @("A","B","a","b")) {
            $choice = Read-Host "请输入 A 或 B"
        }
    } else {
        Write-Warn "gh CLI 未安装。请选择认证方式："
        Write-Info "  [A] 自动安装 gh CLI → OAuth 认证（推荐）"
        Write-Info "  [B] 使用 PAT（无需安装 gh CLI，适合 headless）"
        while ($choice -notin @("A","B","a","b")) {
            $choice = Read-Host "请输入 A 或 B"
        }
    }

    $auth = @{ Mode = ""; PAT = $null }

    if ($choice -in @("A","a")) {
        $auth.Mode = "oauth"

        # 安装 gh CLI（如未安装）
        if (-not $env.GhFound) {
            if ($env.WingetAvailable) {
                Write-Info "正在通过 winget 安装 GitHub CLI..."
                if (-not (Install-WingetPackage "GitHub.cli" "GitHub CLI")) {
                    Write-ErrorMsg "gh CLI 安装失败，请手动安装: https://cli.github.com"
                    Write-Info "或重新运行脚本选择路径 B (PAT)"
                    exit 1
                }
                $env.GhFound = $true
                $env.GhPath = "gh"
            } else {
                Write-ErrorMsg "winget 不可用，请手动安装 gh CLI: https://cli.github.com"
                Write-Info "或重新运行脚本选择路径 B (PAT)"
                exit 1
            }
        }

        # gh auth login（已认证则跳过）
        Write-Info "检查 gh 认证状态..."
        $alreadyAuthed = $false
        & $env.GhPath auth status 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "  gh 已认证，跳过登录步骤"
            $alreadyAuthed = $true
        } else {
            Write-Info "  未认证，正在启动 gh auth login（将打开浏览器）..."
            Write-Info "  请选择: GitHub.com → HTTPS → Login with a web browser"
            & $env.GhPath auth login --hostname github.com --git-protocol https --web
            if ($LASTEXITCODE -ne 0) {
                Write-ErrorMsg "gh auth login 失败，请检查网络或重试"
                exit 1
            }
            Write-Success "GitHub 认证完成"
        }

        # 安装 gh-mcp 扩展（已安装则跳过）
        Write-Info "检查 gh-mcp 扩展..."
        $extList = & $env.GhPath extension list 2>$null | Out-String
        if ($extList -match "shuymn/gh-mcp") {
            Write-Success "  gh-mcp 扩展已安装，跳过"
        } else {
            Write-Info "  正在安装 gh-mcp 扩展..."
            & $env.GhPath extension install shuymn/gh-mcp 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "  gh-mcp 扩展安装完成"
            } else {
                Write-Warn "  gh-mcp 扩展安装可能失败，请手动执行: gh extension install shuymn/gh-mcp"
            }
        }

    } else {
        $auth.Mode = "pat"

        Write-Info ""
        Write-Info "=== 创建 GitHub Personal Access Token ===" -ForegroundColor Yellow
        Write-Info "1. 打开: https://github.com/settings/tokens → Generate new token (classic)"
        Write-Info "2. Note: dm-seek"
        Write-Info "3. Scope: repo（只读）+ read:org（如需组织访问）"
        Write-Info "4. 点击 Generate → 复制 token"
        Write-Info ""
        $pat = Read-MaskedInput "请粘贴 GitHub PAT（输入不显示）："
        if (-not $pat) {
            Write-ErrorMsg "PAT 不能为空，已退出"
            exit 1
        }
        $auth.PAT = $pat

        # 写入用户环境变量
        [Environment]::SetEnvironmentVariable("GITHUB_TOKEN", $pat, "User")
        $env:GITHUB_TOKEN = $pat
        Write-Success "GITHUB_TOKEN 已写入用户环境变量"
        Write-Warn "注意：需重启终端使环境变量对所有进程生效"
    }

    Write-Info ""
    return $auth
}

# ============================================================
# Phase 3: 仓库配置
# ============================================================

function Invoke-Phase3($env, $auth) {
    Write-Banner "Phase 3/5: 仓库配置"

    $repos = @{}

    # 尝试加载已有 repos.json
    $reposPath = Join-Path $script:RootDir ".claude\repos.json"
    if (Test-Path $reposPath) {
        try {
            $existing = Get-Content $reposPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($existing.repos) {
                $existing.repos.PSObject.Properties | ForEach-Object {
                    $repos[$_.Name] = @{
                        local = if ($_.Value.local) { @{ path = $_.Value.local.path } } else { $null }
                        remote = @{
                            owner = $_.Value.remote.owner
                            repo = $_.Value.remote.repo
                            branch = $_.Value.remote.branch
                        }
                    }
                }
                Write-Info "已加载现有配置: $($repos.Count) 个仓库"
            }
        } catch {
            Write-Warn "现有 repos.json 解析失败，将重新创建"
            $repos = @{}
        }
    }

    # --- 路径 A: 本地仓库 ---
    if ($env.LocalRepos.Count -gt 0) {
        Write-Info "发现 $($env.LocalRepos.Count) 个本地仓库："
        for ($i = 0; $i -lt $env.LocalRepos.Count; $i++) {
            $r = $env.LocalRepos[$i]
            $mark = if ($repos.ContainsKey($r.Slug)) { "[已配置]" } else { "" }
            Write-Info "  [$($i+1)] $($r.Slug) — $($r.OwnerRepo) [$($r.Branch)] $mark"
        }
        Write-Info "  [A] 全部添加"
        Write-Info "  [回车] 跳过本地仓库"
        $sel = Read-Host "输入编号(逗号分隔)、A 全部添加、或回车跳过"

        if ($sel -eq "A" -or $sel -eq "a") {
            foreach ($r in $env.LocalRepos) {
                $repos[$r.Slug] = @{
                    local = @{ path = $r.Path }
                    remote = @{
                        owner = ($r.OwnerRepo -split "/")[0]
                        repo = ($r.OwnerRepo -split "/")[1]
                        branch = $r.Branch
                    }
                }
            }
            Write-Success "已添加全部 $($env.LocalRepos.Count) 个仓库"
        } elseif ($sel) {
            $nums = $sel -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^\d+$" }
            foreach ($n in $nums) {
                $idx = [int]$n - 1
                if ($idx -ge 0 -and $idx -lt $env.LocalRepos.Count) {
                    $r = $env.LocalRepos[$idx]
                    $repos[$r.Slug] = @{
                        local = @{ path = $r.Path }
                        remote = @{
                            owner = ($r.OwnerRepo -split "/")[0]
                            repo = ($r.OwnerRepo -split "/")[1]
                            branch = $r.Branch
                        }
                    }
                    Write-Success "已添加: $($r.Slug)"
                }
            }
        }
    }

    # --- 路径 B: 远端仓库 ---
    Write-Info ""
    Write-Info "是否需要从远端浏览并 Clone 仓库？[Y/N]"
    $wantRemote = Read-Host "(Y=是 / N=否)"
    if ($wantRemote -eq "Y" -or $wantRemote -eq "y") {
        if (-not $env.GhFound -or $auth.Mode -ne "oauth") {
            Write-Warn "远端仓库浏览需要 gh CLI + OAuth 认证"
            Write-Warn "当前认证模式: $($auth.Mode)，跳过远端仓库"
        } else {
            $ghPath = $env.GhPath

            # 确定范围
            Write-Info "  输入 GitHub org 名浏览组织仓库，或回车浏览个人仓库："
            $org = Read-Host "  Org（回车=个人）"
            $baseQuery = ""
            if ($org) {
                $baseQuery = "org:$org"
            } else {
                try {
                    $me = & $ghPath api user -q ".login" 2>$null
                    if ($me) { $baseQuery = "user:$me" }
                } catch { }
            }
            if (-not $baseQuery) {
                Write-Warn "无法确定搜索范围，跳过远端仓库"
                return $repos
            }

            # 交互式浏览循环
            $page = 1
            $perPage = 15
            $keyword = ""
            $selectedSlugs = @{}  # 记录已选 slug → 避免重复 clone
            $dmRepos = Join-Path $script:RootDir "dm_repos"
            if (-not (Test-Path $dmRepos)) {
                New-Item -ItemType Directory -Path $dmRepos -Force | Out-Null
            }

            while ($true) {
                # 构建搜索查询
                $searchQuery = $baseQuery
                if ($keyword) { $searchQuery = "$baseQuery $keyword in:name,description" }

                Write-Info "`n  搜索: $searchQuery  [第 $page 页]"
                $repoList = @()
                $totalCount = 0
                try {
                    $apiUrl = "search/repositories?q=$([uri]::EscapeDataString($searchQuery))&per_page=$perPage&page=$page&sort=updated"
                    $result = & $ghPath api $apiUrl --jq ".items[] | {fullName: .full_name, description: .description, defaultBranch: .default_branch}" 2>$null
                    $totalJson = & $ghPath api $apiUrl --jq ".total_count" 2>$null
                    if ($totalJson) { $totalCount = [int]$totalJson }
                    if ($result) {
                        $repoList = $result | ConvertFrom-Json
                        if ($repoList -isnot [array]) { $repoList = @($repoList) }
                    }
                } catch {
                    Write-Warn "  搜索请求失败，请检查网络或 gh 认证状态"
                }

                if ($repoList.Count -eq 0) {
                    Write-Warn "  本页无结果"
                    $page = [Math]::Max(1, $page - 1)
                } else {
                    $totalPages = [Math]::Ceiling($totalCount / $perPage)
                    Write-Info "  共 $totalCount 个仓库，第 $page/$totalPages 页："
                    Write-Info "  ─────────────────────────────────────────────"
                    for ($i = 0; $i -lt $repoList.Count; $i++) {
                        $r = $repoList[$i]
                        $idx = $i + 1
                        $mark = if ($selectedSlugs.ContainsKey(($r.fullName -split "/")[1])) { " [已选]" } else { "" }
                        $desc = if ($r.description) { " — $($r.description)" } else { "" }
                        if ($desc.Length -gt 80) { $desc = $desc.Substring(0, 77) + "..." }
                        Write-Info "    [$idx]$mark $($r.fullName)$desc"
                    }
                    Write-Info "  ─────────────────────────────────────────────"
                }

                # 操作菜单
                Write-Info ""
                Write-Info "  [#] 输入编号(逗号分隔) clone 仓库   [N] 下一页   [P] 上一页"
                Write-Info "  [S] 搜索关键词                       [D] 完成"
                $cmd = Read-Host "  >"

                if ($cmd -eq "D" -or $cmd -eq "d") {
                    break
                } elseif ($cmd -eq "N" -or $cmd -eq "n") {
                    if ($page -lt $totalPages) { $page++ } else { Write-Warn "  已是最后一页" }
                } elseif ($cmd -eq "P" -or $cmd -eq "p") {
                    if ($page -gt 1) { $page-- } else { Write-Warn "  已是第一页" }
                } elseif ($cmd -eq "S" -or $cmd -eq "s") {
                    $keyword = Read-Host "  搜索关键词（回车清除）"
                    $page = 1  # 新搜索从第1页开始
                } elseif ($cmd -match "^\d") {
                    $nums = $cmd -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^\d+$" }
                    foreach ($n in $nums) {
                        $idx = [int]$n - 1
                        if ($idx -ge 0 -and $idx -lt $repoList.Count) {
                            $r = $repoList[$idx]
                            $slug = ($r.fullName -split "/")[1]
                            $owner = ($r.fullName -split "/")[0]
                            if ($selectedSlugs.ContainsKey($slug)) {
                                Write-Warn "  $slug 已选择，跳过"
                                continue
                            }
                            $branch = if ($r.defaultBranch) { $r.defaultBranch } else { "main" }
                            $clonePath = Join-Path $dmRepos $slug

                            Write-Info "  Clone: $($r.fullName) → dm_repos/$slug ..."
                            try {
                                git clone --branch $branch "https://github.com/$($r.fullName).git" $clonePath 2>&1 | Out-Null
                                if ($LASTEXITCODE -eq 0) {
                                    $repos[$slug] = @{
                                        local = @{ path = (Resolve-Path $clonePath).Path }
                                        remote = @{ owner = $owner; repo = $slug; branch = $branch }
                                    }
                                    $selectedSlugs[$slug] = $true
                                    Write-Success "    $slug clone 完成"
                                } else {
                                    Write-Warn "    $slug clone 失败（权限不足或网络问题）"
                                }
                            } catch {
                                Write-Warn "    $slug clone 失败: $_"
                            }
                        }
                    }
                }
            }
        }
    }

    # --- 写入 repos.json ---
    $reposJson = @{ repos = $repos }
    $reposDir = Join-Path $script:RootDir ".claude"
    if (-not (Test-Path $reposDir)) {
        New-Item -ItemType Directory -Path $reposDir -Force | Out-Null
    }
    $reposJson | ConvertTo-Json -Depth 4 | Out-File -FilePath $reposPath -Encoding UTF8 -Force
    Write-Success "`n.claude/repos.json 已写入（$($repos.Count) 个仓库）"

    Write-Info ""
    return $repos
}

# ============================================================
# Phase 4: 配置生成
# ============================================================

function Invoke-Phase4($auth) {
    Write-Banner "Phase 4/5: 配置生成"

    $mcpPath = Join-Path $script:RootDir ".mcp.json"

    # 已有 .mcp.json 且非空 → 保留
    if ((Test-Path $mcpPath) -and ((Get-Content $mcpPath -Raw -Encoding UTF8).Trim() -ne "{}")) {
        Write-Warn ".mcp.json 已存在且非空，保留现有配置不覆盖"
    } else {
        if ($auth.Mode -eq "oauth") {
            $mcpJson = @{
                mcpServers = @{
                    github = @{
                        command = "gh"
                        args = @("mcp")
                        env = @{ GITHUB_READ_ONLY = "1" }
                    }
                }
            }
        } else {
            $mcpJson = @{
                mcpServers = @{
                    github = @{
                        type = "http"
                        url = "https://api.githubcopilot.com/mcp"
                        headers = @{
                            Authorization = "Bearer `${GITHUB_TOKEN}"
                            "X-MCP-Readonly" = "true"
                        }
                    }
                }
            }
        }
        $mcpJson | ConvertTo-Json -Depth 3 | Out-File -FilePath $mcpPath -Encoding UTF8 -Force
        Write-Success ".mcp.json 已生成（$($auth.Mode) 模式）"
    }

    # 校验
    $files = @(
        @{Path=$mcpPath; Name=".mcp.json"},
        @{Path=(Join-Path $script:RootDir ".claude\repos.json"); Name=".claude/repos.json"}
    )
    foreach ($f in $files) {
        if (Test-Path $f.Path) {
            Write-Success "  $($f.Name) 就绪"
        } else {
            Write-Warn "  $($f.Name) 缺失"
        }
    }

    Write-Info ""
}

# ============================================================
# Phase 5: 连通性自检 + 就绪报告
# ============================================================

function Invoke-Phase5($env, $auth, $repos) {
    Write-Banner "Phase 5/5: 连通性自检"

    # GitHub
    Write-Info "[GitHub]"
    if ($auth.Mode -eq "oauth" -and $env.GhFound) {
        $ghStatus = & $env.GhPath auth status 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "  gh 认证状态: OK"
        } else {
            Write-Warn "  gh 认证状态异常，请运行: gh auth login"
        }
    } elseif ($auth.Mode -eq "pat") {
        Write-Info "  PAT 模式: 请重启 Claude Code 后运行 /mcp 确认 github server 已连接"
    }

    # Jira 提示
    Write-Info "[Jira]"
    Write-Info "  在 Claude Code 中依次执行："
    Write-Info "    1. /plugin install atlassian@claude-plugins-official"
    Write-Info "    2. /mcp → Atlassian → Authenticate → 浏览器 OAuth"

    # Obsidian
    Write-Info "[Obsidian KB]"
    if ($env.ObsidianPath) {
        Write-Success "  Obsidian CLI: $($env.ObsidianPath)"
        Write-Info "  在终端执行设置环境变量："
        Write-Info "    `$env:DMSEEK_OBSIDIAN_CLI = `"$($env.ObsidianPath)`""
    } else {
        Write-Warn "  Obsidian CLI 未找到（KB 功能需手动配置）"
    }

    # 就绪报告
    Write-Banner "dm-seek 初始化完成"
    Write-Info "配置摘要："
    Write-Info "  GitHub 认证: $($auth.Mode.ToUpper())"
    Write-Info "  已配置仓库: $($repos.Count) 个"
    if ($repos.Count -gt 0) {
        foreach ($slug in $repos.Keys) {
            $r = $repos[$slug]
            $local = if ($r.local) { $r.local.path } else { "(仅远端)" }
            Write-Info "    $slug → $local"
        }
    }
    Write-Info ""
    Write-Success "下一步: 在 Claude Code 中运行 /mcp 确认 github server 已连接，然后执行："
    Write-Success "  claude --agent dongmei-ma"
    Write-Info ""
}

# ============================================================
# Main
# ============================================================

function Main {
    Write-Host @"
[36m
  ╔══════════════════════════════════════════════════╗
  ║              dm-seek（马冬梅计划）                  ║
  ║           Windows 一键初始化脚本                    ║
  ╚══════════════════════════════════════════════════╝
[0m
"@

    Write-Info "运行目录: $script:RootDir"
    Write-Info ""

    # Phase 1
    $env = Invoke-Phase1

    # Phase 2
    $auth = Invoke-Phase2 $env

    # Phase 3
    $repos = Invoke-Phase3 $env $auth

    # Phase 4
    Invoke-Phase4 $auth

    # Phase 5
    Invoke-Phase5 $env $auth $repos

    Read-Host "按回车键退出"
}

Main
