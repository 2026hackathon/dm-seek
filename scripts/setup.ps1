<#
.SYNOPSIS
    dm-seek Windows 一键初始化脚本
.DESCRIPTION
    自动探测环境、引导 GitHub 认证、配置仓库、生成 .mcp.json 和 repos.json。
    兼容 Windows PowerShell 5.1+（Win 10+ 自带）。
    支持重复运行——已有配置会增量合并而非覆盖。
#>
#Requires -Version 5.1

# 最早输出——确保用户能看到脚本已启动
Write-Host "dm-seek setup.ps1 启动中..." -ForegroundColor Cyan

# RootDir = 项目根目录。如果脚本在 scripts/ 子目录下，取上一级；否则取脚本自身所在目录。
try {
    $script:RootDir = $PSScriptRoot
    if ((Split-Path -Leaf $script:RootDir) -eq "scripts") {
        $script:RootDir = Split-Path -Parent $script:RootDir
    }
    $script:RootDir = (Resolve-Path $script:RootDir).Path
} catch {
    Write-Host "错误: 无法解析脚本根目录: $_" -ForegroundColor Red
    Write-Host "PSScriptRoot: $PSScriptRoot" -ForegroundColor Red
    Write-Host "请确保从脚本所在目录或 scripts/ 子目录运行。" -ForegroundColor Red
    Read-Host "按回车键退出"
    exit 1
}

$ErrorActionPreference = "Stop"

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

function Get-BranchChoice($env, $owner, $repo, $localPath, $defaultBranch) {
    $branches = @()
    # 方式 1: 本地仓库 → git ls-remote
    if ($localPath -and (Test-Path $localPath)) {
        try {
            $raw = git -C $localPath ls-remote --heads origin 2>$null
            if ($raw) {
                $branches = $raw -split "`n" | ForEach-Object {
                    if ($_ -match "refs/heads/(.+)$") { $Matches[1] }
                } | Where-Object { $_ }
            }
        } catch { }
    }
    # 方式 2: gh CLI
    if ($branches.Count -eq 0 -and $env.GhFound -and $owner -and $repo) {
        try {
            $raw = & $env.GhPath api "repos/$owner/$repo/branches" --jq ".[].name" 2>$null
            if ($raw) { $branches = $raw -split "`n" | Where-Object { $_ } }
        } catch { }
    }

    if ($branches.Count -gt 0) {
        Write-Info "    可用分支（默认: $defaultBranch）："
        for ($j = 0; $j -lt $branches.Count; $j++) {
            $mark = if ($branches[$j] -eq $defaultBranch) { " [默认]" } else { "" }
            Write-Info "      [$($j+1)] $($branches[$j])$mark"
        }
        $bSel = Read-Host "    选择分支编号（回车使用默认）"
        if ($bSel -match "^\d+$") {
            $bIdx = [int]$bSel - 1
            if ($bIdx -ge 0 -and $bIdx -lt $branches.Count) { return $branches[$bIdx] }
        }
    }
    return $defaultBranch
}

# ============================================================
# Phase 1: 环境探测
# ============================================================

function Invoke-Phase1 {
    Write-Banner "Phase 1/6: 环境探测"

    $env = @{
        GitFound = $false
        GhFound = $false
        GhPath = $null
        ObsidianPath = $null
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

    Write-Info ""
    return $env
}

# ============================================================
# Phase 2: GitHub 认证
# ============================================================

function Invoke-Phase2($env) {
    Write-Banner "Phase 2/6: GitHub 认证"

    $auth = @{ Mode = ""; PAT = $null }

    # ---- 路径 A: gh CLI + OAuth ----
    Write-Info "[路径 A] gh CLI + OAuth"
    $aCliOk = $false; $aAuthOk = $false; $aMcpOk = $false

    if (-not $env.GhFound) {
        if ($env.WingetAvailable) {
            Write-Info "  gh CLI 未安装，通过 winget 自动安装..."
            if (Install-WingetPackage "GitHub.cli" "GitHub CLI") {
                $env.GhFound = $true
                $env.GhPath = "gh"
            }
        }
    }
    if ($env.GhFound) {
        Write-Success "  gh CLI: $($env.GhPath)"
        $aCliOk = $true

        & $env.GhPath auth status 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "  gh auth: 已认证"
            $aAuthOk = $true
        } else {
            Write-Warn "  gh auth: 未认证（运行 gh auth login 配置）"
        }

        if ($aAuthOk) {
            $extList = & $env.GhPath extension list 2>$null | Out-String
            if ($extList -match "shuymn/gh-mcp") {
                Write-Success "  gh-mcp: 已安装"
                $aMcpOk = $true
            } else {
                Write-Warn "  gh-mcp: 未安装（运行 gh extension install shuymn/gh-mcp）"
            }
        }
    } else {
        Write-Warn "  gh CLI: 未安装"
    }

    $aReady = $aCliOk -and $aAuthOk -and $aMcpOk
    if ($aReady) { Write-Success "  [路径 A] OAuth 就绪" }
    else         { Write-Warn "  [路径 A] OAuth 未就绪" }

    # ---- 路径 B: PAT ----
    Write-Info ""
    Write-Info "[路径 B] Personal Access Token"
    $existingPAT = $env:GITHUB_TOKEN
    if (-not $existingPAT) {
        $existingPAT = [Environment]::GetEnvironmentVariable("GITHUB_TOKEN", "User")
    }
    $bReady = $false
    if ($existingPAT) {
        Write-Success "  GITHUB_TOKEN: 已设置"
        $bReady = $true
    } else {
        Write-Warn "  GITHUB_TOKEN: 未设置"
    }

    # ---- 输出状态 ----
    Write-Info ""
    Write-Info "  认证状态："
    if ($aReady) { Write-Success "    [A] gh CLI + OAuth — 就绪" }
    else         { Write-Warn  "    [A] gh CLI + OAuth — 未就绪" }
    if ($bReady) { Write-Success "    [B] PAT — 就绪" }
    else         { Write-Warn  "    [B] PAT — 未就绪" }

    # ---- 默认选择 ----
    if ($aReady) {
        $auth.Mode = "oauth"
    } elseif ($bReady) {
        $auth.Mode = "pat"
        $auth.PAT = $existingPAT
    }

    # ---- 允许切换 ----
    if ($aReady -or $bReady) {
        Write-Info ""
        Write-Success ">> 当前使用路径 $($auth.Mode.ToUpper())"
        $change = Read-Host "  是否需要修改？[Y=修改 / 回车=保持]"
        if ($change -eq "Y" -or $change -eq "y") {
            Write-Info "  可选："
            if ($aReady) { Write-Info "    [A] gh CLI + OAuth" }
            else         { Write-Info "    [A] gh CLI + OAuth（未就绪）" }
            if ($bReady) { Write-Info "    [B] PAT" }
            else         { Write-Info "    [B] PAT（未就绪）" }
            $pick = Read-Host "  选择"
            if ($pick -eq "A" -or $pick -eq "a") {
                if ($aReady) {
                    $auth.Mode = "oauth"
                    Write-Success ">> 已切换为路径 A（OAuth）"
                } else {
                    Write-Warn "  路径 A 未就绪：需安装 gh CLI 并认证"
                    Write-Info "    1. winget install GitHub.cli"
                    Write-Info "    2. gh auth login"
                    Write-Info "    3. gh extension install shuymn/gh-mcp"
                }
            } elseif ($pick -eq "B" -or $pick -eq "b") {
                if ($bReady) {
                    $auth.Mode = "pat"
                    $auth.PAT = $existingPAT
                    Write-Success ">> 已切换为路径 B（PAT）"
                } else {
                    Write-Warn "  路径 B 未就绪：需设置 GITHUB_TOKEN"
                    Write-Info "    1. 创建 PAT: https://github.com/settings/tokens"
                    Write-Info "    2. 运行: setx GITHUB_TOKEN <你的token>"
                    Write-Info "    3. 重启终端后重新运行本脚本"
                }
            }
        }
    } else {
        # A/B 都不满足，引导用户
        Write-Warn "→ 路径 A 和 B 均未就绪"
        Write-Info ""
        Write-Info "  请选择以下方式之一配置 GitHub 认证："
        Write-Info ""
        Write-Info "  [A] gh CLI + OAuth（推荐，零 PAT）"
        Write-Info "      1. 下载安装: https://cli.github.com"
        Write-Info "      2. 终端运行: gh auth login"
        Write-Info "      3. 安装扩展: gh extension install shuymn/gh-mcp"
        Write-Info "      4. 重新运行本脚本"
        Write-Info ""
        Write-Info "  [B] Personal Access Token（无需 gh CLI）"
        Write-Info "      1. 打开: https://github.com/settings/tokens → Generate new token (classic)"
        Write-Info "      2. Note: dm-seek  |  Scope: repo（只读）"
        Write-Info "      3. 运行: setx GITHUB_TOKEN <你的token>"
        Write-Info "      4. 重启终端，重新运行本脚本"
        Write-Info ""
        $manual = Read-Host "  或现在输入 PAT（回车退出）"
        if ($manual) {
            $auth.Mode = "pat"
            $auth.PAT = $manual
            [Environment]::SetEnvironmentVariable("GITHUB_TOKEN", $manual, "User")
            $env:GITHUB_TOKEN = $manual
            Write-Success "  GITHUB_TOKEN 已写入用户环境变量"
            Write-Warn "  注意：需重启终端使环境变量对所有进程生效"
        } else {
            Write-ErrorMsg "GitHub 认证未配置，已退出。请按上述指引配置后重新运行。"
            exit 1
        }
    }

    Write-Info ""
    return $auth
}

# ============================================================
# Phase 3: 仓库配置
# ============================================================

function Invoke-Phase3($env, $auth) {
    Write-Banner "Phase 3/6: 仓库配置"

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
                foreach ($slug in $repos.Keys) {
                    $r = $repos[$slug]
                    $localInfo = if ($r.local) { $r.local.path } else { "(仅远端)" }
                    Write-Info "  $slug — $($r.remote.owner)/$($r.remote.repo) [$($r.remote.branch)]"
                }
            }
        } catch {
            Write-Warn "现有 repos.json 解析失败，将重新创建"
            $repos = @{}
        }
    }

    # ---- 操作菜单 ----
    Write-Info ""
    Write-Info "[A] 调整仓库分支"
    Write-Info "[B] 扫描加载仓库"
    Write-Info "[回车] 保持现有配置，继续"
    $choice = Read-Host "选择操作"

    # ---- 选项 A: 调整分支 ----
    if ($choice -eq "A" -or $choice -eq "a") {
        if ($repos.Count -eq 0) {
            Write-Warn "  无已配置仓库，无法调整分支"
        } else {
            Write-Info "  已配置仓库："
            $slugs = @($repos.Keys)
            for ($i = 0; $i -lt $slugs.Count; $i++) {
                $s = $slugs[$i]
                $r = $repos[$s]
                Write-Info "    [$($i+1)] $s — $($r.remote.owner)/$($r.remote.repo) [$($r.remote.branch)]"
            }
            $sel = Read-Host "  选择仓库编号"
            if ($sel -match "^\d+$") {
                $idx = [int]$sel - 1
                if ($idx -ge 0 -and $idx -lt $slugs.Count) {
                    $slug = $slugs[$idx]
                    $r = $repos[$slug]
                    $owner = $r.remote.owner
                    $repo = $r.remote.repo

                    # 取远端分支列表
                    $branches = @()
                    # 方式 1: 本地仓库有 git → git ls-remote
                    if ($r.local -and $r.local.path -and (Test-Path $r.local.path)) {
                        try {
                            $raw = git -C $r.local.path ls-remote --heads origin 2>$null
                            if ($raw) {
                                $branches = $raw -split "`n" | ForEach-Object {
                                    if ($_ -match "refs/heads/(.+)$") { $Matches[1] }
                                } | Where-Object { $_ }
                            }
                        } catch { }
                    }
                    # 方式 2: gh CLI
                    if ($branches.Count -eq 0 -and $env.GhFound -and $owner -and $repo) {
                        try {
                            $raw = & $env.GhPath api "repos/$owner/$repo/branches" --jq ".[].name" 2>$null
                            if ($raw) { $branches = $raw -split "`n" | Where-Object { $_ } }
                        } catch { }
                    }

                    if ($branches.Count -gt 0) {
                        Write-Info "  $slug 可用分支（当前: $($r.remote.branch)）："
                        for ($j = 0; $j -lt $branches.Count; $j++) {
                            $mark = if ($branches[$j] -eq $r.remote.branch) { " [当前]" } else { "" }
                            Write-Info "    [$($j+1)] $($branches[$j])$mark"
                        }
                        $bSel = Read-Host "  选择分支编号（回车保持当前）"
                        if ($bSel -match "^\d+$") {
                            $bIdx = [int]$bSel - 1
                            if ($bIdx -ge 0 -and $bIdx -lt $branches.Count) {
                                $r.remote.branch = $branches[$bIdx]
                                Write-Success "  $slug 分支已更新: $($branches[$bIdx])"
                            }
                        }
                    } else {
                        Write-Warn "  无法获取远端分支列表（无本地仓库且 gh CLI 不可用）"
                        $newBranch = Read-Host "  手动输入新分支名（当前: $($r.remote.branch)，回车保持）"
                        if ($newBranch) {
                            $r.remote.branch = $newBranch
                            Write-Success "  $slug 分支已更新: $newBranch"
                        }
                    }
                }
            }
        }
    }

    # ---- 选项 B: 扫描加载仓库 ----
    if ($choice -eq "B" -or $choice -eq "b") {
    # --- 路径 A: 本地仓库 ---
    Write-Info "是否需要扫描本地目录查找 git 仓库？[Y/N]"
    $wantScan = Read-Host "(Y=是 / N=否)"
    if ($wantScan -eq "Y" -or $wantScan -eq "y") {
        $scanDirs = @(
            "$env:USERPROFILE\dev", "$env:USERPROFILE\projects",
            "D:\dev", "D:\dev_repository", "D:\projects",
            "C:\dev", "C:\projects"
        )
        $foundRepos = @()
        foreach ($dir in $scanDirs) {
            if (-not (Test-Path $dir)) { continue }
            Write-Info "  扫描 $dir ..."
            $gitDirs = Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName ".git") }
            foreach ($gd in $gitDirs) {
                $remoteUrl = $null; $branch = $null
                try {
                    $remoteUrl = (git -C $gd.FullName remote get-url origin 2>$null)
                    $branch = (git -C $gd.FullName branch --show-current 2>$null)
                } catch { }
                if ($remoteUrl) {
                    $slug = Split-Path -Leaf $gd.FullName
                    $ownerRepo = ""
                    if ($remoteUrl -match "github\.com[:/](.+)/(.+?)(\.git)?$") {
                        $ownerRepo = "$($Matches[1])/$($Matches[2])"
                    }
                    $foundRepos += @{
                        Path = $gd.FullName
                        Slug = $slug
                        OwnerRepo = $ownerRepo
                        Branch = if ($branch) { $branch } else { "main" }
                    }
                }
            }
        }
        if ($foundRepos.Count -gt 0) {
            Write-Info "  发现 $($foundRepos.Count) 个仓库："
            for ($i = 0; $i -lt $foundRepos.Count; $i++) {
                $r = $foundRepos[$i]
                $mark = if ($repos.ContainsKey($r.Slug)) { "[已配置]" } else { "" }
                Write-Info "    [$($i+1)] $($r.Slug) — $($r.OwnerRepo) [$($r.Branch)] $mark"
            }
            Write-Info "    [A] 全部添加"
            Write-Info "    [回车] 跳过"
            $sel = Read-Host "  输入编号(逗号分隔)、A 全部添加、或回车跳过"
            if ($sel -eq "A" -or $sel -eq "a") {
                foreach ($r in $foundRepos) {
                    if (-not $repos.ContainsKey($r.Slug)) {
                        $repos[$r.Slug] = @{
                            local = @{ path = $r.Path }
                            remote = @{
                                owner = ($r.OwnerRepo -split "/")[0]
                                repo = ($r.OwnerRepo -split "/")[1]
                                branch = $r.Branch
                            }
                        }
                    }
                }
                Write-Success "  已添加全部"
            } elseif ($sel) {
                $nums = $sel -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^\d+$" }
                foreach ($n in $nums) {
                    $idx = [int]$n - 1
                    if ($idx -ge 0 -and $idx -lt $foundRepos.Count) {
                        $r = $foundRepos[$idx]
                        if (-not $repos.ContainsKey($r.Slug)) {
                            $owner = ($r.OwnerRepo -split "/")[0]
                            $repo = ($r.OwnerRepo -split "/")[1]
                            $chosen = Get-BranchChoice $env $owner $repo $r.Path $r.Branch
                            $repos[$r.Slug] = @{
                                local = @{ path = $r.Path }
                                remote = @{
                                    owner = $owner
                                    repo = $repo
                                    branch = $chosen
                                }
                            }
                            Write-Success "    已添加: $($r.Slug) [$chosen]"
                        }
                    }
                }
            }
        } else {
            Write-Warn "  未发现本地 git 仓库"
        }
    }

    # --- 路径 A-2: 手动输入 ---
    Write-Info "是否手动添加本地仓库？[Y/N]"
    $wantManual = Read-Host "(Y=是 / N=否)"
    while ($wantManual -eq "Y" -or $wantManual -eq "y") {
        $localPath = Read-Host "输入本地仓库路径（回车跳过）"
        if (-not $localPath) { break }
        if (-not (Test-Path (Join-Path $localPath ".git"))) {
            Write-Warn "  不是 git 仓库，请重新输入"
            continue
        }
        $slug = Split-Path -Leaf $localPath
        $remoteUrl = (git -C $localPath remote get-url origin 2>$null)
        $branch = (git -C $localPath branch --show-current 2>$null)
        $owner = ""
        $repo = $slug
        if ($remoteUrl -match "github\.com[:/](.+)/(.+?)(\.git)?$") {
            $owner = $Matches[1]
            $repo = $Matches[2]
        }
        $resolvedPath = (Resolve-Path $localPath).Path
        $defaultBr = if ($branch) { $branch } else { "main" }
        $chosen = Get-BranchChoice $env $owner $repo $resolvedPath $defaultBr
        $repos[$slug] = @{
            local = @{ path = $resolvedPath }
            remote = @{
                owner = $owner
                repo = $repo
                branch = $chosen
            }
        }
        Write-Success "  已添加: $slug ($owner/$repo) [$chosen]"
        Write-Info "继续添加？[Y/N]"
        $wantManual = Read-Host "(Y=是 / N=否)"
    }

    # --- 路径 B: 远端仓库 ---
    Write-Info ""
    Write-Info "是否需要从远端浏览并 Clone 仓库？[Y/N]"
    $wantRemote = Read-Host "(Y=是 / N=否)"
    if ($wantRemote -eq "Y" -or $wantRemote -eq "y") {
        # 判断 gh CLI 是否可用且有认证（OAuth 或 PAT 均可）
        $ghAvailable = $false
        if (-not $env.GhFound) {
            Write-Warn "gh CLI 未安装，跳过远端仓库浏览"
        } elseif ($auth.Mode -eq "oauth") {
            & $env.GhPath auth status 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $ghAvailable = $true
            } else {
                Write-Warn "gh 认证状态异常，跳过远端仓库浏览。请运行: gh auth login"
            }
        } else {
            # PAT 模式：Phase 2 已设置 GITHUB_TOKEN，gh CLI 可直接使用
            $env:GITHUB_TOKEN = $auth.PAT
            $ghAvailable = $true
        }

        if ($ghAvailable) {
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
            } else {
                # 交互式浏览循环
                $page = 1
                $perPage = 15
                $keyword = ""
                $selectedSlugs = @{}  # 记录已选 slug → 避免重复 clone
                $dmRepos = Join-Path $script:RootDir "dm-repos"
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

                            Write-Info "  Clone: $($r.fullName) → dm-repos/$slug ..."
                            try {
                                # PAT 模式用 token 认证，OAuth 模式走 gh CLI keyring
                                $cloneUrl = if ($auth.Mode -eq "pat" -and $auth.PAT) {
                                    "https://$($auth.PAT)@github.com/$($r.fullName).git"
                                } else {
                                    "https://github.com/$($r.fullName).git"
                                }
                                # 后台 job 运行 clone，主线程解析进度画进度条
                                $job = Start-Job -ScriptBlock {
                                    param($url, $branch, $path)
                                    git clone --branch $branch $url $path --progress 2>&1
                                } -ArgumentList $cloneUrl, $branch, $clonePath
                                $percent = 0
                                while ($job.State -eq "Running") {
                                    $latest = Receive-Job $job 2>$null | Select-Object -Last 1
                                    if ($latest -match '(\d+)%') { $percent = [int]$Matches[1] }
                                    $barLen = [Math]::Floor($percent / 2.5)
                                    $bar = "[" + ("#" * $barLen) + (" " * (40 - $barLen)) + "]"
                                    Write-Host "`r  Clone $bar $percent%" -NoNewline
                                    Start-Sleep -Milliseconds 200
                                }
                                # 收尾
                                $allOutput = Receive-Job $job 2>$null
                                Remove-Job $job -Force
                                if ($percent -ge 100) { $percent = 100 }
                                $barLen = [Math]::Floor($percent / 2.5)
                                $bar = "[" + ("#" * $barLen) + (" " * (40 - $barLen)) + "]"
                                Write-Host "`r  Clone $bar 100%"
                                # 检查结果：从输出中找错误
                                $exitCode = 0
                                $allOutput | ForEach-Object {
                                    if ($_ -match "^fatal:") { $exitCode = 1; Write-Warn "    $_" }
                                }
                                if ($auth.PAT -and $allOutput) {
                                    $allOutput | ForEach-Object {
                                        $line = $_ -replace [regex]::Escape($auth.PAT), "***"
                                        if ($line -match "^fatal:" -or $line -match "^error:") { Write-Warn "    $line" }
                                    }
                                }
                                if ($exitCode -eq 0) {
                                    $resolvedPath = (Resolve-Path $clonePath).Path
                                    $chosen = Get-BranchChoice $env $owner $slug $resolvedPath $branch
                                    $repos[$slug] = @{
                                        local = @{ path = $resolvedPath }
                                        remote = @{ owner = $owner; repo = $slug; branch = $chosen }
                                    }
                                    $selectedSlugs[$slug] = $true
                                    Write-Success "    $slug clone 完成 [$chosen]"
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
    }
    }  # 选项 B 结束

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
# Phase 4: KB Vault 初始化
# ============================================================

function Invoke-Phase4($repos) {
    Write-Banner "Phase 4/6: KB Vault 初始化"

    if ($repos.Count -eq 0) {
        Write-Warn "  repos.json 无仓库，跳过 vault 初始化"
        Write-Info ""
        return
    }

    $kbDir = Join-Path $script:RootDir "dm-kbs"
    if (-not (Test-Path $kbDir)) {
        New-Item -ItemType Directory -Path $kbDir -Force | Out-Null
    }

    # ---- 下载 Knowlery 插件（所有 vault 共享一份） ----
    $knowleryCache = Join-Path $kbDir ".knowlery-cache"
    $knowleryReady = $false
    if (-not (Test-Path $knowleryCache)) {
        Write-Info "  下载 Knowlery 插件..."
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $release = Invoke-RestMethod -Uri "https://api.github.com/repos/JayJiangCT/knowlery/releases/latest" -TimeoutSec 15
            New-Item -ItemType Directory -Path $knowleryCache -Force | Out-Null
            foreach ($file in @("main.js", "manifest.json", "styles.css")) {
                $asset = $release.assets | Where-Object { $_.name -eq $file }
                if ($asset) {
                    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile (Join-Path $knowleryCache $file) -TimeoutSec 30
                }
            }
            # 验证三文件齐全
            $allOk = $true
            foreach ($f in @("main.js", "manifest.json", "styles.css")) {
                if (-not (Test-Path (Join-Path $knowleryCache $f))) { $allOk = $false; break }
            }
            if ($allOk) {
                $knowleryReady = $true
                Write-Success "  Knowlery 插件下载完成"
            } else {
                Write-Warn "  Knowlery 下载不完整，将跳过自动安装"
            }
        } catch {
            Write-Warn "  Knowlery 下载失败（网络原因或 GitHub 不可达）: $_"
        }
    } else {
        $knowleryReady = $true
        Write-Info "  Knowlery 插件缓存已存在"
    }

    # ---- 注册到 Obsidian ----
    $obsidianConfig = Join-Path $env:APPDATA "obsidian\obsidian.json"
    $obsidianAvailable = Test-Path $obsidianConfig
    $registeredCount = 0
    if ($obsidianAvailable) {
        try {
            $config = Get-Content $obsidianConfig -Raw -Encoding UTF8 | ConvertFrom-Json
            $vaults = [ordered]@{}
            if ($config.vaults) {
                $config.vaults.PSObject.Properties | ForEach-Object {
                    $vaults[$_.Name] = $_.Value
                }
            }
            $configSaved = $false

            foreach ($slug in $repos.Keys) {
                $vaultPath = Join-Path $kbDir "${slug}_kb"
                $already = $false
                foreach ($v in $vaults.Values) {
                    $p = if ($v.path) { $v.path } else { $v.Path }
                    if ($p -eq $vaultPath) { $already = $true; break }
                }
                if (-not $already) {
                    $vid = [Guid]::NewGuid().ToString("N").Substring(0, 16)
                    $vaults[$vid] = [PSCustomObject]@{
                        path = $vaultPath
                        ts   = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
                        open = $false
                    }
                    $registeredCount++
                    $configSaved = $true
                }
            }

            if ($configSaved) {
                $config.vaults = $vaults
                $config | ConvertTo-Json -Depth 10 | Out-File -FilePath $obsidianConfig -Encoding UTF8 -Force
            }
        } catch {
            Write-Warn "  Obsidian 注册失败: $_"
        }
    }

    # ---- 逐仓库创建 vault ----
    $created = @()
    $skipped = @()
    foreach ($slug in $repos.Keys) {
        $vaultPath = Join-Path $kbDir "${slug}_kb"
        $obsidianDir = Join-Path $vaultPath ".obsidian"
        $initMarker = Join-Path $vaultPath ".obsidian\.dmseek-init"

        if (Test-Path $initMarker) {
            $skipped += $slug
            continue
        }

        # vault 骨架
        if (-not (Test-Path $obsidianDir)) {
            New-Item -ItemType Directory -Path $obsidianDir -Force | Out-Null
        }
        @{} | ConvertTo-Json | Out-File -FilePath (Join-Path $obsidianDir "app.json") -Encoding UTF8 -Force

        # 安装 Knowlery 插件
        if ($knowleryReady) {
            $pluginDir = Join-Path $obsidianDir "plugins\knowlery"
            if (-not (Test-Path $pluginDir)) {
                New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
                Copy-Item (Join-Path $knowleryCache "main.js") $pluginDir -Force
                Copy-Item (Join-Path $knowleryCache "manifest.json") $pluginDir -Force
                Copy-Item (Join-Path $knowleryCache "styles.css") $pluginDir -Force
            }
        }

        # 预写 community-plugins.json
        @("knowlery") | ConvertTo-Json | Out-File -FilePath (Join-Path $obsidianDir "community-plugins.json") -Encoding UTF8 -Force

        # 标记已初始化
        "setup.ps1 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $initMarker -Encoding UTF8 -Force
        $created += $slug
    }

    # ---- 回写 kb 路径到 repos.json ----
    if ($created.Count -gt 0) {
        $reposPath = Join-Path $script:RootDir ".claude\repos.json"
        try {
            $reposConfig = Get-Content $reposPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($slug in $created) {
                $repoProp = $reposConfig.repos.PSObject.Properties | Where-Object { $_.Name -eq $slug }
                if ($repoProp) {
                    $vaultName = "${slug}_kb"
                    $repoProp.Value | Add-Member -MemberType NoteProperty -Name "kb" -Value ([PSCustomObject]@{
                        vault = $vaultName
                        path = "dm-kbs/$vaultName"
                    }) -Force
                }
            }
            $reposConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $reposPath -Encoding UTF8 -Force
            Write-Success "  kb 路径已写入 repos.json"
        } catch {
            Write-Warn "  repos.json kb 字段更新失败: $_"
        }
    }

    # ---- 汇总 ----
    if ($created.Count -gt 0) {
        Write-Success "  已创建 vault: $($created -join ', ')"
        if ($knowleryReady) {
            Write-Success "  Knowlery 插件已预装，community-plugins.json 已配置"
        }
        if ($registeredCount -gt 0) {
            Write-Success "  已注册 $registeredCount 个 vault 到 Obsidian"
        }
        Write-Info ""
        Write-Info "  ┌─────────────────────────────────────────────────────┐"
        Write-Info "  │  下一步（每个 vault 只需做一次）:                      │"
        Write-Info "  │  1. 打开 Obsidian → 选择 {repo}_kb vault              │"
        Write-Info "  │  2. Settings → Community plugins → Turn on           │"
        Write-Info "  │  3. Knowlery 自动初始化 vault 结构                    │"
        Write-Info "  └─────────────────────────────────────────────────────┘"
    }
    if ($skipped.Count -gt 0) {
        Write-Info "  已存在，跳过: $($skipped -join ', ')"
    }
    if (-not $obsidianAvailable) {
        Write-Warn "  Obsidian 未安装或从未启动——vault 已创建但未注册"
        Write-Warn "  安装 Obsidian 后手动打开 dm-kbs/{repo}_kb/"
    }
    if (-not $knowleryReady) {
        Write-Warn "  Knowlery 未自动安装——请在 Obsidian 中搜索安装 Knowlery 插件"
    }

    Write-Info ""
}

# ============================================================
# Phase 5: 配置生成
# ============================================================

function Invoke-Phase5($auth) {
    Write-Banner "Phase 5/6: 配置生成"

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
# Phase 6: 连通性自检 + 就绪报告
# ============================================================

function Invoke-Phase6($env, $auth, $repos) {
    Write-Banner "Phase 6/6: 连通性自检"

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
        [Environment]::SetEnvironmentVariable("DMSEEK_OBSIDIAN_CLI", $env.ObsidianPath, "User")
        Write-Success "  DMSEEK_OBSIDIAN_CLI 已写入用户环境变量"
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
    Invoke-Phase4 $repos

    # Phase 5
    Invoke-Phase5 $auth

    # Phase 6
    Invoke-Phase6 $env $auth $repos

    Read-Host "按回车键退出"
}

Main
