<#
.SYNOPSIS
    dm-seek Windows 一键初始化脚本
.DESCRIPTION
    自动探测环境、引导 GitHub 认证、配置仓库、生成 .mcp.json 和 repos.json。
    兼容 Windows PowerShell 5.1+（Win 10+ 自带）。
    支持重复运行——已有配置会增量合并而非覆盖。
#>
#Requires -Version 5.1

param(
    [string]$Phase,          # 直接跳转到指定 Phase（1-6），跳过菜单
    [switch]$Auto            # 全量线性执行（兼容旧用法，等效于依次执行 Phase 1-6）
)

# 最早输出——确保用户能看到脚本已启动
Write-Host "dm-seek windows-setup.ps1 启动中..." -ForegroundColor Cyan
if ($Phase) { Write-Host "  参数: -Phase $Phase" -ForegroundColor Cyan }
if ($Auto)  { Write-Host "  参数: -Auto（全量执行）" -ForegroundColor Cyan }

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

# ── 无 BOM 写 JSON（PS5.1 的 Out-File -Encoding UTF8 会写 UTF-8 BOM，严格 JSON 解析器/jq/Obsidian 可能报错）──
function Write-JsonFile($Object, $Path, $Depth = 10, [switch]$Compress) {
    $json = $Object | ConvertTo-Json -Depth $Depth -Compress:$Compress
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

# ── 深度把 ConvertFrom-Json 的 PSCustomObject 转 hashtable（PS5.1 无 ConvertFrom-Json -AsHashtable）──
function ConvertTo-HashtableDeep($obj) {
    if ($obj -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}; foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-HashtableDeep $p.Value }; return $h
    } elseif ($obj -is [System.Collections.IEnumerable] -and $obj -isnot [string]) {
        return @($obj | ForEach-Object { ConvertTo-HashtableDeep $_ })
    } else { return $obj }
}

# ── 带超时的 gh auth status（防 OAuth 未登录/网络异常时前台调用挂起，尤其 -Auto 无人值守）；返回 $true=已认证 ──
function Test-GhAuthStatus($ghPath) {
    if (-not $ghPath) { return $false }
    $job = Start-Job { param($p) & $p auth status 2>&1 | Out-Null; $LASTEXITCODE } -ArgumentList $ghPath
    if (Wait-Job $job -Timeout 10) {
        $code = Receive-Job $job; Remove-Job $job -Force; return ($code -eq 0)
    }
    Remove-Job $job -Force; return $false
}

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
        $wingetOut = winget install --id $packageId --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -or $wingetOut -match 'already installed|已安装') {
            Write-Success "  $displayName 安装完成（或已安装）"
            return $true
        } else {
            Write-Warn "  winget 安装 $displayName 返回非零退出码（$LASTEXITCODE），请检查"
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
        } catch { Write-Debug "Get-BranchChoice ls-remote failed: $_" }
    }
    # 方式 2: gh CLI
    if ($branches.Count -eq 0 -and $env.GhFound -and $owner -and $repo) {
        try {
            $raw = & $env.GhPath api "repos/$owner/$repo/branches" --jq ".[].name" 2>$null
            if ($raw) { $branches = $raw -split "`n" | Where-Object { $_ } }
        } catch { Write-Debug "Get-BranchChoice gh api failed: $_" }
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
# 状态检测（供菜单使用）
# ============================================================

$script:EnvState = $null    # Phase 1 结果缓存
$script:AuthState = $null   # Phase 2 结果缓存
$script:ReposState = $null  # Phase 3 结果缓存

function Get-InitStatus {
    <#
    .SYNOPSIS
        轻量探测当前环境状态（不修改任何文件），返回结构化对象供菜单展示。
    #>
    $status = [ordered]@{
        GitFound       = $false
        GitVersion     = ""
        GhFound        = $false
        GhVersion      = ""
        GhAuthOk       = $false
        GhMcpOk        = $false
        ObsidianFound  = $false
        ObsidianPath   = ""
        WingetAvailable = $false
        AuthMode       = ""       # oauth / pat / none
        AuthMcpConsistent = $true # .mcp.json 与认证模式是否一致
        RepoCount      = 0
        RepoLocalCount = 0
        RepoRemoteOnlyCount = 0
        EnabledRepoCount = 0
        DisabledRepoCount = 0
        KbVaultTotal   = 0
        KbVaultDone    = 0
        McpJsonMode    = ""       # oauth / pat / empty
        McpJsonExists  = $false
    }

    # --- winget ---
    try { $null = winget --version 2>$null; $status.WingetAvailable = $true } catch { }

    # --- git ---
    if (Test-Command "git") {
        $status.GitFound = $true
        $status.GitVersion = (git --version 2>$null) -replace "git version ", ""
    }

    # --- gh CLI ---
    $ghPaths = @("gh", "$env:ProgramFiles\GitHub CLI\gh.exe", "${env:ProgramFiles(x86)}\GitHub CLI\gh.exe", "$env:LOCALAPPDATA\GitHubCLI\gh.exe", "$env:USERPROFILE\scoop\shims\gh.exe")
    foreach ($p in $ghPaths) {
        if (Test-Command $p) {
            $status.GhFound = $true
            $status.GhVersion = (& $p --version 2>$null | Select-Object -First 1) -replace "gh version ", ""
            $script:EnvState = @{ GhPath = $p; GhFound = $true }
            $ghPath = $p
            break
        }
    }
    if ($status.GhFound) {
        # PAT 模式下跳过 gh auth status（无需 OAuth 令牌，command 必然挂起）
        $mcpCheck = Join-Path $script:RootDir ".mcp.json"
        $isPat = $false
        if (Test-Path $mcpCheck) {
            try { $mcpJson = Get-Content $mcpCheck -Raw -Encoding UTF8 | ConvertFrom-Json; $ghCfg = $mcpJson.mcpServers.github; if ($ghCfg -and ($ghCfg.args.GITHUB_PAT -or ($ghCfg.headers.Authorization -match "GITHUB_TOKEN"))) { $isPat = $true } } catch { }
        }
        if (-not $isPat) {
            $job = Start-Job { param($p) & $p auth status 2>$null >$null; $LASTEXITCODE } -ArgumentList $ghPath
            $completed = Wait-Job $job -Timeout 10
            if ($completed) {
                $exitCode = Receive-Job $job
                $exitOk = ($exitCode -eq 0)
            } else {
                $exitOk = $false
                Write-Debug "Get-InitStatus: gh auth status timed out"
            }
            Remove-Job $job -Force
        } else { $exitOk = $false }
        if ($exitOk) {
            $status.GhAuthOk = $true
            $extList = & $ghPath extension list 2>$null | Out-String
            if ($extList -match "shuymn/gh-mcp") { $status.GhMcpOk = $true }
        }
    }

    # --- Obsidian CLI ---
    $obsPaths = @("$env:DMSEEK_OBSIDIAN_CLI", "D:\obsidian\Obsidian.com", "$env:LOCALAPPDATA\obsidian\Obsidian.com", "$env:USERPROFILE\AppData\Local\obsidian\Obsidian.com")
    foreach ($p in $obsPaths) {
        if ($p -and (Test-Path $p)) {
            $status.ObsidianFound = $true
            $status.ObsidianPath = $p
            break
        }
    }

    # --- 认证模式判定 ---
    $mcpPath = Join-Path $script:RootDir ".mcp.json"
    if (Test-Path $mcpPath) {
        try {
            $mcpJson = Get-Content $mcpPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $status.McpJsonExists = $true
            $ghCfg = $mcpJson.mcpServers.github
            if (-not $ghCfg) {
                $status.McpJsonMode = "empty"
            } elseif ($ghCfg.command -eq "gh") {
                $status.McpJsonMode = "oauth"
            } elseif ($ghCfg.args.GITHUB_PAT -or ($ghCfg.headers.Authorization -match "GITHUB_TOKEN")) {
                $status.McpJsonMode = "pat"
            }
        } catch {
            $status.McpJsonMode = "empty"
        }
    }

    # --- 当前实际认证模式 ---
    # .mcp.json 是用户选择的权威来源；为空时才回退到环境探测
    $existingPAT = $env:GITHUB_TOKEN
    if (-not $existingPAT) { $existingPAT = [Environment]::GetEnvironmentVariable("GITHUB_TOKEN", "User") }
    if ($status.McpJsonMode -ne "empty") {
        # .mcp.json 已配置 → 以 .mcp.json 为准（用户显式选择）
        $status.AuthMode = $status.McpJsonMode
    } elseif ($status.GhFound -and $status.GhAuthOk -and $status.GhMcpOk) {
        $status.AuthMode = "oauth"
    } elseif ($existingPAT) {
        $status.AuthMode = "pat"
    } else {
        $status.AuthMode = "none"
    }

    # --- .mcp.json 与认证模式一致性 ---
    if ($status.AuthMode -eq "none" -or $status.McpJsonMode -eq "empty") {
        $status.AuthMcpConsistent = $true  # 未配置时不标记不一致
    } elseif ($status.AuthMode -ne $status.McpJsonMode) {
        $status.AuthMcpConsistent = $false
    }

    # --- repos.json ---
    $reposPath = Join-Path $script:RootDir ".claude\repos.json"
    if (Test-Path $reposPath) {
        try {
            $reposConfig = Get-Content $reposPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($reposConfig.repos) {
                $props = $reposConfig.repos.PSObject.Properties
                foreach ($prop in $props) {
                    if ($prop.Value.local -and $prop.Value.local.path) { $status.RepoLocalCount++ }
                    else { $status.RepoRemoteOnlyCount++ }
                    # enable 字段：默认 true
                    $repoEnable = if ($null -ne $prop.Value.enable) { [bool]$prop.Value.enable } else { $true }
                    if ($repoEnable) { $status.EnabledRepoCount++ } else { $status.DisabledRepoCount++ }
                    if ($prop.Value.kb) {
                        $status.KbVaultTotal++
                        $vaultPath = Join-Path $script:RootDir $prop.Value.kb.path
                        if (Test-Path $vaultPath) {
                            $status.KbVaultDone++
                        }
                    }
                }
                # 从子计数器推导 RepoCount，保证内部一致性，避免 PSCustomObject.Properties.Count 的边界行为
                $status.RepoCount = [int]$status.RepoLocalCount + [int]$status.RepoRemoteOnlyCount
            }
        } catch { Write-Debug "Get-InitStatus JSON parse failed: $_" }
    }

    return $status
}

function Show-Status($s) {
    Write-Host ("`n" + "=" * 60) -ForegroundColor Cyan
    Write-Host "  dm-seek 初始化状态" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan

    # 环境
    $gitIcon = if ($s.GitFound) { "[OK]" } else { "[MISS]" }
    $gitStr = if ($s.GitFound) { "git $($s.GitVersion)" } else { "未安装" }
    $ghIcon = if ($s.GhFound) { "[OK]" } else { "[MISS]" }
    $ghStr = if ($s.GhFound) { "gh $($s.GhVersion)" } else { "未安装" }
    $obsIcon = if ($s.ObsidianFound) { "[OK]" } else { "[WARN]" }
    $obsStr = if ($s.ObsidianFound) { $s.ObsidianPath } else { "未找到" }

    Write-Host ("  git:       $gitIcon $gitStr") -ForegroundColor $(if($s.GitFound){'Green'}else{'Red'})
    Write-Host ("  gh CLI:    $ghIcon $ghStr") -ForegroundColor $(if($s.GhFound){'Green'}else{'Yellow'})
    Write-Host ("  Obsidian:  $obsIcon $obsStr") -ForegroundColor $(if($s.ObsidianFound){'Green'}else{'Yellow'})

    # 认证
    $authStr = switch ($s.AuthMode) {
        "oauth" { "OAuth (gh CLI + gh-mcp)" }
        "pat"   { "PAT (GITHUB_TOKEN)" }
        default { "未配置" }
    }
    $authColor = if ($s.AuthMode -eq "none") { "Red" } else { "Green" }
    Write-Host ("  GitHub:    $($s.AuthMode.ToUpper()) — $authStr") -ForegroundColor $authColor

    # .mcp.json 一致性
    $mcpStr = if ($s.McpJsonMode -eq "empty") { "空（待生成）" } else { $s.McpJsonMode.ToUpper() }
    $mcpConsistent = if ($s.AuthMcpConsistent) { "[OK]" } else { "[WARN]" }
    $mcpColor = if ($s.AuthMcpConsistent) { "Green" } else { "Yellow" }
    Write-Host ("  .mcp.json: $mcpConsistent $mcpStr") -ForegroundColor $mcpColor
    if (-not $s.AuthMcpConsistent) {
        Write-Host ("            [WARN] .mcp.json 与认证模式不一致——请运行 [5] 更新") -ForegroundColor Yellow
    }

    # 仓库
    $repoStr = "$($s.RepoCount) 个仓库 ($($s.RepoLocalCount) 有本地, $($s.RepoRemoteOnlyCount) 仅远端)"
    if ($s.DisabledRepoCount -gt 0) {
        $repoStr += " ($($s.EnabledRepoCount) 启用, $($s.DisabledRepoCount) 禁用)"
    }
    $repoColor = if ($s.RepoCount -gt 0) { "Green" } else { "Yellow" }
    Write-Host ("  repos.json: $repoStr") -ForegroundColor $repoColor

    # KB vault
    if ($s.RepoCount -gt 0) {
        $kbStr = "$($s.KbVaultDone)/$($s.KbVaultTotal) 已初始化"
        $kbColor = if ($s.KbVaultDone -eq $s.KbVaultTotal -and $s.KbVaultTotal -gt 0) { "Green" } else { "Yellow" }
        Write-Host ("  KB vault:   $kbStr") -ForegroundColor $kbColor
    }

    Write-Host ("=" * 60) -ForegroundColor Cyan
}

function Show-MainMenu($s) {
    Write-Host ""
    Write-Host "  操作：" -ForegroundColor White
    Write-Host "    [1] 重新探测环境" -ForegroundColor White
    Write-Host "    [2] 配置 GitHub 认证 (当前: $($s.AuthMode.ToUpper()))" -ForegroundColor White
    Write-Host "    [3] 管理仓库配置 ($($s.RepoCount) 个仓库)" -ForegroundColor White
    Write-Host "    [4] 初始化 KB Vault ($($s.KbVaultDone)/$($s.KbVaultTotal))" -ForegroundColor White
    Write-Host "    [5] 生成 .mcp.json (当前: $($s.McpJsonMode.ToUpper()))" -ForegroundColor White
    Write-Host "    [6] 连通性自检" -ForegroundColor White
    Write-Host "    [7] 检查仓库更新" -ForegroundColor White
    Write-Host "    [8] 刷新依赖图" -ForegroundColor White
    Write-Host "    [0] 退出" -ForegroundColor White
    Write-Host ""
    $choice = Read-Host "  选择"
    return $choice.Trim()
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
    # 若无传入 env（菜单模式），自动探测
    if (-not $env) { $env = Get-InitStatus; $env.GhPath = if ($env.GhFound) { "gh" } else { $null }; $env.WingetAvailable = $env.WingetAvailable }

    # 记录切换前的 .mcp.json 认证模式（用于检测用户是否切换了模式）
    $prevMcpMode = (Get-InitStatus).McpJsonMode
    if ($prevMcpMode -eq "empty") { $prevMcpMode = "" }  # 空 "empty" 统一为空字符串

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

        if (Test-GhAuthStatus $env.GhPath) {
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

    # ---- 检测当前实际配置 ----
    $currentMode = $null
    $mcpPath = Join-Path $script:RootDir ".mcp.json"
    if (Test-Path $mcpPath) {
        try {
            $mcp = Get-Content $mcpPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $ghCfg = $mcp.mcpServers.github
            if ($ghCfg) {
                if ($ghCfg.command -eq "gh") { $currentMode = "oauth" }
                elseif ($ghCfg.args.GITHUB_PAT -or ($ghCfg.headers.Authorization -match "GITHUB_TOKEN")) { $currentMode = "pat" }
            }
        } catch { }
    }
    if (-not $currentMode) {
        if (Test-GhAuthStatus $env.GhPath) { $currentMode = "oauth" }
    }
    if (-not $currentMode) {
        if ($aReady) { $currentMode = "oauth" }
        elseif ($bReady) { $currentMode = "pat" }
    }

    $auth.Mode = $currentMode
    if ($currentMode -eq "pat") { $auth.PAT = $existingPAT }

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
        $manual = Read-MaskedInput "  或现在输入 PAT（回车退出）"
        if ($manual) {
            $auth.Mode = "pat"
            $auth.PAT = $manual
            try { [Environment]::SetEnvironmentVariable("GITHUB_TOKEN", $manual, "User") } catch { Write-Warn "  环境变量写入失败（权限不足）" }
            $env:GITHUB_TOKEN = $manual
            Write-Success "  GITHUB_TOKEN 已写入用户环境变量"
            Write-Warn "  注意：需重启终端使环境变量对所有进程生效"
        } else {
            Write-ErrorMsg "GitHub 认证未配置，已退出。请按上述指引配置后重新运行。"
            exit 1
        }
    }

    # 检测认证模式是否变更：比较用户选择的新模式与 .mcp.json 记录的旧模式
    # 注意：不能用 Get-InitStatus().AuthMode 比较前后（此时 .mcp.json 尚未更新，前后相同）
    # 当 .mcp.json 为空或与用户选择不一致时均视为变更，触发 Phase 5 自动生成
    $auth.ModeChanged = ($auth.Mode -ne "none" -and ($prevMcpMode -ne $auth.Mode))

    Write-Info ""
    return $auth
}

# ============================================================
# Phase 3: 仓库配置
# ============================================================

function Invoke-Phase3($env, $auth) {
    # 若无传入参数（菜单模式），自动探测
    if (-not $env) { $env = Get-InitStatus; $env.GhPath = if ($env.GhFound) { "gh" } else { $null } }
    if (-not $auth) { $auth = @{ Mode = (Get-InitStatus).AuthMode } }
    # 尝试从环境变量读取 PAT
    if ($auth.Mode -eq "pat" -and -not $auth.PAT) {
        $auth.PAT = $env:GITHUB_TOKEN
        if (-not $auth.PAT) { $auth.PAT = [Environment]::GetEnvironmentVariable("GITHUB_TOKEN", "User") }
    }

    Write-Banner "Phase 3/6: 仓库配置"

    $repos = @{}

    # 尝试加载已有 repos.json
    $reposPath = Join-Path $script:RootDir ".claude\repos.json"
    if (Test-Path $reposPath) {
        try {
            $existing = Get-Content $reposPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($existing.repos) {
                $existing.repos.PSObject.Properties | ForEach-Object {
                    $entry = @{}
                    $_.Value.PSObject.Properties | ForEach-Object { $entry[$_.Name] = $_.Value }
                    $repos[$_.Name] = $entry
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
    Write-Info "[C] 启用/禁用仓库"
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
                                $oldBranch = $r.remote.branch
                                $r.remote.branch = $branches[$bIdx]
                                Write-Success "  $slug 分支已更新: $($branches[$bIdx])"
                                # 如果本地仓库存在，真正 checkout 到新分支
                                if ($r.local -and $r.local.path -and (Test-Path (Join-Path $r.local.path ".git"))) {
                                    Write-Info "    切换本地仓库分支: $oldBranch -> $($r.remote.branch) ..."
                                    $prevEAP = $ErrorActionPreference
                                    $ErrorActionPreference = "Continue"
                                    git -C $r.local.path fetch origin $r.remote.branch >$null 2>&1
                                    if ($LASTEXITCODE -ne 0) {
                                        Write-Warn "    fetch 失败（分支可能不存在或网络问题）"
                                    } else {
                                        git -C $r.local.path checkout $r.remote.branch 2>$null >$null
                                        if ($LASTEXITCODE -ne 0) {
                                            Write-Warn "    checkout 失败（可能有未提交的本地改动）"
                                        } else {
                                            Write-Success "    已切换到 $($r.remote.branch)"
                                        }
                                    }
                                    $ErrorActionPreference = $prevEAP
                                }
                            }
                        }
                    } else {
                        Write-Warn "  无法获取远端分支列表（无本地仓库且 gh CLI 不可用）"
                        $newBranch = Read-Host "  手动输入新分支名（当前: $($r.remote.branch)，回车保持）"
                        if ($newBranch) {
                            $oldBranch = $r.remote.branch
                            $r.remote.branch = $newBranch
                            Write-Success "  $slug 分支已更新: $newBranch"
                            if ($r.local -and $r.local.path -and (Test-Path (Join-Path $r.local.path ".git"))) {
                                Write-Info "    切换本地仓库分支: $oldBranch -> $newBranch ..."
                                $prevEAP = $ErrorActionPreference
                                $ErrorActionPreference = "Continue"
                                git -C $r.local.path fetch origin $newBranch >$null 2>&1
                                if ($LASTEXITCODE -ne 0) {
                                    Write-Warn "    fetch 失败（分支可能不存在或网络问题）"
                                } else {
                                    git -C $r.local.path checkout $newBranch 2>$null >$null
                                    if ($LASTEXITCODE -ne 0) {
                                        Write-Warn "    checkout 失败（可能有未提交的本地改动）"
                                    } else {
                                        Write-Success "    已切换到 $newBranch"
                                    }
                                }
                                $ErrorActionPreference = $prevEAP
                            }
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
            if (Test-GhAuthStatus $env.GhPath) {
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

                if (-not $totalPages) { $totalPages = 1 }   # 兜底：首页即无结果时 $totalPages 未定义会使翻页判断失效
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
                                # PAT 模式用 credential helper 避免 PAT 暴露到进程列表
                                $cloneUrl = "https://github.com/$($r.fullName).git"
                                # 后台 job 运行 clone，主线程解析进度画进度条
                                $job = Start-Job -ScriptBlock {
                                    param($url, $branch, $path, $pat)
                                    $env:GIT_TERMINAL_PROMPT = "0"
                                    if ($pat) {
                                        $env:DMSEEK_CLONE_PAT = $pat
                                        $helper = '!f() { echo username=x-access-token; echo password=$DMSEEK_CLONE_PAT; }; f'
                                        git -c "credential.helper=" -c "credential.helper=$helper" clone --branch $branch $url $path --progress 2>&1
                                    } else {
                                        git clone --branch $branch $url $path --progress 2>&1
                                    }
                                    "__GITEXIT__$LASTEXITCODE"
                                } -ArgumentList $cloneUrl, $branch, $clonePath, $auth.PAT
                                while ($job.State -eq "Running") {
                                $percent = 0
                                    $latest = Receive-Job $job 2>$null | Select-Object -Last 1
                                    if ($latest -match '(\d+)%') { $percent = [int]$Matches[1] }
                                    $barLen = [Math]::Floor($percent / 2.5)
                                    $bar = "[" + ("#" * $barLen) + (" " * (40 - $barLen)) + "]"
                                    Write-Host "`r  Clone $bar $percent%" -NoNewline
                                    Start-Sleep -Milliseconds 200
                                }
                                # 收尾
                                $rawOutput = Receive-Job $job 2>$null
                                Remove-Job $job -Force
                                # 分离 git clone 真实退出码标记（不再仅靠扫描 fatal: 判定成败）
                                $gitExit = 0; $allOutput = @()
                                foreach ($ln in $rawOutput) {
                                    if ("$ln" -match '^__GITEXIT__(\d+)$') { $gitExit = [int]$Matches[1] }
                                    else { $allOutput += $ln }
                                }
                                if ($percent -ge 100) { $percent = 100 }
                                $barLen = [Math]::Floor($percent / 2.5)
                                $bar = "[" + ("#" * $barLen) + (" " * (40 - $barLen)) + "]"
                                Write-Host "`r  Clone $bar 100%"
                                # 以 git clone 真实退出码为准，再扫描 fatal: 作补充展示
                                $exitCode = $gitExit
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
                                    # 如果用户选择的分支与 clone 时不同，切过去
                                    if ($chosen -ne $branch) {
                                        Write-Info "    切换分支: $branch -> $chosen ..."
                                        $prevEAP = $ErrorActionPreference
                                        $ErrorActionPreference = "Continue"
                                        git -C $resolvedPath fetch origin $chosen 2>$null >$null
                                        if ($LASTEXITCODE -ne 0) {
                                            Write-Warn "    fetch 失败（分支可能不存在或网络问题）"
                                        } else {
                                            git -C $resolvedPath checkout $chosen 2>$null >$null
                                            if ($LASTEXITCODE -ne 0) {
                                                Write-Warn "    checkout 失败（可能有未提交的本地改动）"
                                            } else {
                                                Write-Success "    已切换到 $chosen"
                                            }
                                        }
                                        $ErrorActionPreference = $prevEAP
                                    }
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

    # ---- 选项 C: 启用/禁用仓库 ----
    if ($choice -eq "C" -or $choice -eq "c") {
        if ($repos.Count -eq 0) {
            Write-Warn "  无已配置仓库"
        } else {
            while ($true) {
                Write-Info "`n  仓库启用/禁用状态："
                $slugList = @($repos.Keys)
                for ($i = 0; $i -lt $slugList.Count; $i++) {
                    $s = $slugList[$i]
                    $r = $repos[$s]
                    $enable = if ($null -ne $r.enable) { [bool]$r.enable } else { $true }
                    $statusTxt = if ($enable) { "✓ 启用" } else { "✗ 禁用" }
                    $color = if ($enable) { "Green" } else { "Yellow" }
                    Write-Host "    [$($i+1)] $s — $statusTxt" -ForegroundColor $color
                }
                Write-Info "    [A] 全部启用  [D] 全部禁用  [回车] 返回"
                $sel = Read-Host "  选择（单号/逗号分隔多号/A/D/回车）"
                if (-not $sel) { break }
                if ($sel -eq "A" -or $sel -eq "a") {
                    foreach ($s in $slugList) { $repos[$s].enable = $true }
                    Write-Success "  已全部启用"
                } elseif ($sel -eq "D" -or $sel -eq "d") {
                    foreach ($s in $slugList) { $repos[$s].enable = $false }
                    Write-Success "  已全部禁用"
                } else {
                    $nums = $sel -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^\d+$" }
                    if ($nums.Count -gt 0) {
                        foreach ($n in $nums) {
                            $idx = [int]$n - 1
                            if ($idx -ge 0 -and $idx -lt $slugList.Count) {
                                $slug = $slugList[$idx]
                                $cur = if ($null -ne $repos[$slug].enable) { [bool]$repos[$slug].enable } else { $true }
                                $repos[$slug].enable = (-not $cur)
                                $st = if ($repos[$slug].enable) { "启用" } else { "禁用" }
                                Write-Success "    $slug → $st"
                            }
                        }
                    }
                }
                # 每次操作后即时写回
                $reposJson = $null
                if (Test-Path $reposPath) {
                    try { $reposJson = Get-Content $reposPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
                }
                if (-not $reposJson) { $reposJson = @{} }
                $reposJson.repos = $repos
                Write-JsonFile -Object $reposJson -Path $reposPath -Depth 4
            }
        }
    }

    # --- 写入 repos.json ---
    $reposJson = $null
    if (Test-Path $reposPath) {
        try { $reposJson = Get-Content $reposPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    if (-not $reposJson) { $reposJson = @{} }
    $reposJson.repos = $repos
    $reposDir = Join-Path $script:RootDir ".claude"
    if (-not (Test-Path $reposDir)) {
        New-Item -ItemType Directory -Path $reposDir -Force | Out-Null
    }
    Write-JsonFile -Object $reposJson -Path $reposPath -Depth 4
    Write-Success "`n.claude/repos.json 已写入（$($repos.Count) 个仓库）"

    Write-Info ""
    return $repos
}

# ============================================================
# Phase 4: KB Vault 初始化
# ============================================================

function Invoke-Phase4($repos) {
    # 若无传入 repos（菜单模式），从 repos.json 加载
    if (-not $repos) {
        $repos = @{}
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
                }
            } catch { }
        }
    }

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
                Write-JsonFile -Object $config -Path $obsidianConfig -Depth 10
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
        Write-JsonFile -Object @{} -Path (Join-Path $obsidianDir "app.json")

        # 标记已初始化
        [System.IO.File]::WriteAllText($initMarker, "windows-setup.ps1 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", (New-Object System.Text.UTF8Encoding($false)))
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
            Write-JsonFile -Object $reposConfig -Path $reposPath -Depth 10
            Write-Success "  kb 路径已写入 repos.json"
        } catch {
            Write-Warn "  repos.json kb 字段更新失败: $_"
        }
    }

    # ---- 汇总 ----
    if ($created.Count -gt 0) {
        Write-Success "  已创建 vault: $($created -join ', ')"
        if ($registeredCount -gt 0) {
            Write-Success "  已注册 $registeredCount 个 vault 到 Obsidian"
        }
        Write-Info ""
        Write-Info "  ┌─────────────────────────────────────────────────────┐"
        Write-Info "  │  下一步: 运行 KB-init 生成概念索引                      │"
        Write-Info "  │  /kb-init scope=all                                 │"
        Write-Info "  └─────────────────────────────────────────────────────┘"
    }
    if ($skipped.Count -gt 0) {
        Write-Info "  已存在，跳过: $($skipped -join ', ')"
    }
    if (-not $obsidianAvailable) {
        Write-Warn "  Obsidian 未安装或从未启动——vault 已创建但未注册"
        Write-Warn "  安装 Obsidian 后手动打开 dm-kbs/{repo}_kb/"
    }
    Write-Info ""
}

# ============================================================
# Phase 5: 配置生成
# ============================================================

function Invoke-Phase5($auth) {
    # 若无传入 auth（菜单模式），自动探测
    if (-not $auth -or -not $auth.Mode) {
        $status = Get-InitStatus
        $auth = @{ Mode = $status.AuthMode }
        if ($auth.Mode -eq "pat") {
            $auth.PAT = $env:GITHUB_TOKEN
            if (-not $auth.PAT) { $auth.PAT = [Environment]::GetEnvironmentVariable("GITHUB_TOKEN", "User") }
        }
    }

    Write-Banner "Phase 5/6: 配置生成"

    if ($auth.Mode -eq "none") {
        Write-Warn ".mcp.json 无法生成：GitHub 认证未配置。请先运行 [2] 配置 GitHub 认证。"
        Write-Info ""
        return
    }

    $mcpPath = Join-Path $script:RootDir ".mcp.json"

    # 读旧 .mcp.json（如存在），仅更新 mcpServers.github（保留其它 server）
    if (-not (Test-Path $mcpPath)) {
        $mcpJson = @{ mcpServers = @{} }
    } else {
        try {
            $mcpRaw = Get-Content $mcpPath -Raw -Encoding UTF8
            $mcpJson = $mcpRaw | ConvertFrom-Json
            if ($mcpJson -isnot [hashtable]) { $mcpJson = ConvertTo-HashtableDeep $mcpJson }
        } catch { $mcpJson = @{ mcpServers = @{} } }
        if (-not $mcpJson.ContainsKey('mcpServers') -or $mcpJson['mcpServers'] -isnot [hashtable]) { $mcpJson['mcpServers'] = @{} }
    }
    # github server — 检测 gh 全路径（避免 Claude Code PowerShell 环境找不到 gh）
    $ghCmd = "gh"
    foreach ($p in @("$env:ProgramFiles\GitHub CLI\gh.exe", "$env:LOCALAPPDATA\Programs\GitHub CLI\gh.exe", "$env:USERPROFILE\scoop\shims\gh.exe")) {
        if (Test-Path $p) { $ghCmd = $p; break }
    }
    if ($auth.Mode -eq "oauth") {
        $mcpJson['mcpServers']['github'] = @{ command = $ghCmd; args = @("mcp"); env = @{ GITHUB_READ_ONLY = "1" } }
    } else {
        $mcpJson['mcpServers']['github'] = @{
            type = "http"; url = "https://api.githubcopilot.com/mcp"
            headers = @{ Authorization = "Bearer `${GITHUB_TOKEN}"; "X-MCP-Readonly" = "true" }
        }
    }
    Write-JsonFile -Object $mcpJson -Path $mcpPath -Depth 4
    Write-Success ".mcp.json 已生成（$($auth.Mode) 模式）"

    # Jira/Atlassian Plugin — 写入 settings.json
    $settingsPath = Join-Path $script:RootDir ".claude\settings.json"
    # hashtable 键赋值，避免 PS5.1 下 hashtable+Add-Member+ConvertTo-Json 丢配置（首跑会丢 Jira Plugin）
    $settings = @{}
    if (Test-Path $settingsPath) {
        try { $settings = ConvertTo-HashtableDeep (Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { $settings = @{} }
    }
    if ($settings -isnot [hashtable]) { $settings = @{} }
    # PS 5.1 ConvertFrom-Json 会将单元素数组退化为字符串，强制恢复已知数组字段
    if ($settings.ContainsKey('permissions') -and $settings['permissions'] -is [hashtable]) {
        $perms = $settings['permissions']
        if ($perms.ContainsKey('allow') -and $perms['allow'] -is [string]) { $perms['allow'] = @($perms['allow']) }
        if ($perms.ContainsKey('deny') -and $perms['deny'] -is [string]) { $perms['deny'] = @($perms['deny']) }
        if ($perms.ContainsKey('ask') -and $perms['ask'] -is [string]) { $perms['ask'] = @($perms['ask']) }
    }
    if (-not $settings.ContainsKey('enabledPlugins') -or $settings['enabledPlugins'] -isnot [hashtable]) { $settings['enabledPlugins'] = @{} }
    $settings['enabledPlugins']['atlassian@claude-plugins-official'] = $true
    if (-not $settings.ContainsKey('extraKnownMarketplaces') -or $settings['extraKnownMarketplaces'] -isnot [hashtable]) { $settings['extraKnownMarketplaces'] = @{} }
    if (-not $settings['extraKnownMarketplaces'].ContainsKey('claude-plugins-official')) {
        $settings['extraKnownMarketplaces']['claude-plugins-official'] = @{ source = @{ source = "github"; repo = "anthropics/claude-plugins-official" } }
    }
    Write-JsonFile -Object $settings -Path $settingsPath -Depth 10
    Write-Success "settings.json 已更新（Jira Plugin）"

    # 校验
    $files = @(
        @{Path=$mcpPath; Name=".mcp.json"},
        @{Path=(Join-Path $script:RootDir ".claude\repos.json"); Name=".claude/repos.json"},
        @{Path=$settingsPath; Name=".claude/settings.json"}
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
    # 若无传入参数（菜单模式），自动探测
    if (-not $env) { $env = Get-InitStatus; $env.GhPath = if ($env.GhFound) { "gh" } else { $null }; $env.ObsidianPath = $env.ObsidianPath }
    if (-not $auth) { $auth = @{ Mode = (Get-InitStatus).AuthMode } }
    if (-not $repos) {
        $repos = @{}
        $reposPath = Join-Path $script:RootDir ".claude\repos.json"
        if (Test-Path $reposPath) {
            try {
                $existing = Get-Content $reposPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($existing.repos) { $existing.repos.PSObject.Properties | ForEach-Object { $repos[$_.Name] = $_.Value } }
            } catch { }
        }
    }

    Write-Banner "Phase 6/6: 连通性自检"

    # GitHub
    Write-Info "[GitHub]"
    if ($auth.Mode -eq "oauth" -and $env.GhFound) {
        if (Test-GhAuthStatus $env.GhPath) {
            Write-Success "  gh 认证状态: OK"
        } else {
            Write-Warn "  gh 认证状态异常，请运行: gh auth login"
        }
    } elseif ($auth.Mode -eq "pat") {
        Write-Info "  PAT 模式: 请重启 Claude Code 后运行 /mcp 确认 github server 已连接"
    }

    # Jira
    Write-Info "[Jira]"
    $settingsPath = Join-Path $script:RootDir ".claude\settings.json"
    $jiraConfigured = $false
    if (Test-Path $settingsPath) {
        try {
            $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($settings.enabledPlugins."atlassian@claude-plugins-official") { $jiraConfigured = $true }
        } catch { }
    }
    if ($jiraConfigured) {
        Write-Success "  Jira Plugin 已配置（settings.json）"
    } else {
        Write-Warn "  Jira Plugin 未配置，请运行 [5] 生成配置"
    }
    Write-Info "  首次使用需认证：/mcp → Atlassian → Authenticate → 浏览器 OAuth"

    # Obsidian — 独立重检，不依赖 Phase 1 的缓存结果
    Write-Info "[Obsidian KB]"
    $obsFound = $env.ObsidianPath
    if (-not $obsFound) {
        $obsPaths = @("$env:DMSEEK_OBSIDIAN_CLI", "D:\obsidian\Obsidian.com", "$env:LOCALAPPDATA\obsidian\Obsidian.com", "$env:USERPROFILE\AppData\Local\obsidian\Obsidian.com")
        foreach ($p in $obsPaths) {
            if ($p -and (Test-Path $p)) { $obsFound = $p; break }
        }
    }
    if ($obsFound) {
        Write-Success "  Obsidian CLI: $obsFound"
        try { [Environment]::SetEnvironmentVariable("DMSEEK_OBSIDIAN_CLI", $obsFound, "User") } catch { Write-Warn "  环境变量写入失败（权限不足），请手动设置: `$env:DMSEEK_OBSIDIAN_CLI='$obsFound' " }
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
# 自动扫描：启动时检测 dm-repos/ 和 dm-kbs/ 并补全 repos.json
# ============================================================

function Invoke-AutoScan {
    $reposPath = Join-Path $script:RootDir ".claude\repos.json"
    $repos = @{}
    $reposChanged = $false

    # 加载现有 repos.json
    if (Test-Path $reposPath) {
        try {
            $existing = Get-Content $reposPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($existing.repos) {
                $existing.repos.PSObject.Properties | ForEach-Object {
                    $entry = @{}
                    $_.Value.PSObject.Properties | ForEach-Object { $entry[$_.Name] = $_.Value }
                    $repos[$_.Name] = $entry
                }
            }
        } catch { }
    }

    # ---- 扫描 dm-repos/ ----
    $dmRepos = Join-Path $script:RootDir "dm-repos"
    if (Test-Path $dmRepos) {
        $subDirs = Get-ChildItem $dmRepos -Directory -ErrorAction SilentlyContinue
        foreach ($dir in $subDirs) {
            $gitDir = Join-Path $dir.FullName ".git"
            if (-not (Test-Path $gitDir)) { continue }

            $slug = $dir.Name
            $resolvedPath = $dir.FullName

            # 检查是否已在 repos.json 中（按 local path 匹配）
            $alreadyTracked = $false
            foreach ($r in $repos.Values) {
                if ($r.local -and $r.local.path -eq $resolvedPath) {
                    $alreadyTracked = $true
                    break
                }
            }
            if ($alreadyTracked) { continue }

            # 检测远端信息
            $remoteUrl = $null; $branch = $null
            try { $remoteUrl = (git -C $resolvedPath remote get-url origin 2>$null) } catch { }
            try { $branch = (git -C $resolvedPath branch --show-current 2>$null) } catch { }
            if (-not $branch) { $branch = "main" }

            $owner = ""; $repoName = $slug
            if ($remoteUrl -match "github\.com[:/](.+)/(.+?)(\.git)?$") {
                $owner = $Matches[1]
                $repoName = $Matches[2]
            }

            # 如果 repos 中已有同名 slug 但无 local path，补全 local
            if ($repos.ContainsKey($slug) -and -not $repos[$slug].local) {
                $repos[$slug].local = @{ path = $resolvedPath }
                if (-not $repos[$slug].remote) {
                    $repos[$slug].remote = @{ owner = $owner; repo = $repoName; branch = $branch }
                }
                $reposChanged = $true
                Write-Info "  [auto] $slug — 补全本地路径: $resolvedPath"
            } elseif (-not $repos.ContainsKey($slug)) {
                $repos[$slug] = @{
                    local = @{ path = $resolvedPath }
                    remote = @{ owner = $owner; repo = $repoName; branch = $branch }
                }
                $reposChanged = $true
                Write-Info "  [auto] $slug — 自动发现: $owner/$repoName [$branch]"
            }
        }
    }

    # ---- 扫描 dm-kbs/ ----
    $dmKbs = Join-Path $script:RootDir "dm-kbs"
    if (Test-Path $dmKbs) {
        $vaultDirs = Get-ChildItem $dmKbs -Directory -ErrorAction SilentlyContinue
        foreach ($vdir in $vaultDirs) {
            $vaultName = $vdir.Name  # 如 hdr-delivery-project_kb
            if ($vaultName -notmatch "^(.+)_kb$") { continue }
            $matchedSlug = $Matches[1]

            # 查找匹配的 repo
            if ($repos.ContainsKey($matchedSlug)) {
                if (-not $repos[$matchedSlug].kb) {
                    $repos[$matchedSlug].kb = @{
                        vault = $vaultName
                        path = "dm-kbs/$vaultName"
                    }
                    $reposChanged = $true
                    Write-Info "  [auto] $matchedSlug — 关联 KB vault: $vaultName"
                }
            }
        }
    }

    # ---- 写入 repos.json ----
    if ($reposChanged) {
        $reposDir = Join-Path $script:RootDir ".claude"
        if (-not (Test-Path $reposDir)) {
            New-Item -ItemType Directory -Path $reposDir -Force | Out-Null
        }
        $reposObj = $null
        if (Test-Path $reposPath) {
            try { $reposObj = Get-Content $reposPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
        }
        if (-not $reposObj) { $reposObj = @{} }
        $reposObj.repos = $repos
        Write-JsonFile -Object $reposObj -Path $reposPath -Depth 4
    }
}

# ============================================================
# Menu 7: 检查仓库更新
# ============================================================

function Invoke-UpdateCheck {
    Write-Banner "检查 dm-repos 仓库更新"

    $reposPath = Join-Path $script:RootDir ".claude\repos.json"
    if (-not (Test-Path $reposPath)) {
        Write-Warn "repos.json 不存在，请先运行 [3] 管理仓库配置"
        Write-Info ""
        return
    }

    try {
        $reposConfig = Get-Content $reposPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Warn "repos.json 解析失败"
        Write-Info ""
        return
    }

    if (-not $reposConfig.repos) {
        Write-Warn "repos.json 中无仓库"
        Write-Info ""
        return
    }

    # 遍历所有配置了本地路径的仓库，检查远端更新
    $repoStatus = @()
    foreach ($prop in $reposConfig.repos.PSObject.Properties) {
        $slug = $prop.Name
        $localPath = if ($prop.Value.local) { $prop.Value.local.path } else { $null }
        $branch = if ($prop.Value.remote) { $prop.Value.remote.branch } else { "main" }

        if (-not $localPath -or -not (Test-Path (Join-Path $localPath ".git"))) {
            $repoStatus += @{ Slug=$slug; Path=$localPath; Ok=$false; Behind=0; Ahead=0; Error="本地仓库不可达" }
            continue
        }

        try {
            # fetch 远端
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            cmd /c "git -C `"$localPath`" fetch origin $branch" 2>$null >$null
            $ErrorActionPreference = $prevEAP
        } catch { }

        # 比较本地 HEAD 与 origin/branch 的差异
        $behind = 0
        $ahead = 0
        try {
            $behind = [int](git -C $localPath rev-list --count HEAD..origin/$branch 2>$null)
            $ahead  = [int](git -C $localPath rev-list --count origin/$branch..HEAD 2>$null)
        } catch { }

        if ($LASTEXITCODE -eq 0) {
            $repoStatus += @{ Slug=$slug; Path=$localPath; Ok=$true; Behind=$behind; Ahead=$ahead; Branch=$branch; Error="" }
        } else {
            $repoStatus += @{ Slug=$slug; Path=$localPath; Ok=$false; Behind=0; Ahead=0; Branch=$branch; Error="远端 $branch 不可达" }
        }
    }

    # 汇总显示
    $updatable = @($repoStatus | Where-Object { $_.Ok -and $_.Behind -gt 0 })
    $errors = @($repoStatus | Where-Object { -not $_.Ok })
    $current = @($repoStatus | Where-Object { $_.Ok -and $_.Behind -eq 0 })

    Write-Info ""
    if ($errors.Count -gt 0) {
        Write-Warn "  不可达:"
        foreach ($e in $errors) { Write-Warn "    $($e.Slug) — $($e.Error)" }
    }

    if ($current.Count -gt 0) {
        Write-Success "  已是最新:"
        foreach ($c in $current) { Write-Success "    $($c.Slug) [$($c.Branch)]" }
    }

    if ($updatable.Count -gt 0) {
        Write-Host "  有待更新:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $updatable.Count; $i++) {
            $u = $updatable[$i]
            Write-Host "    [$($i+1)] $($u.Slug) [$($u.Branch)] — 落后 $($u.Behind) 个提交" -ForegroundColor Yellow
        }

        Write-Info ""
        Write-Info "  [A] 一键全部更新"
        Write-Info "  [#] 输入编号更新单个仓库（逗号分隔多选）"
        Write-Info "  [回车] 跳过"
        Write-Info ""
        $choice = Read-Host "  选择"

        if ($choice -eq "A" -or $choice -eq "a") {
            $toUpdate = $updatable
        } elseif ($choice) {
            $toUpdate = @()
            $nums = $choice -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^\d+$" }
            foreach ($n in $nums) {
                $idx = [int]$n - 1
                if ($idx -ge 0 -and $idx -lt $updatable.Count) {
                    $toUpdate += $updatable[$idx]
                }
            }
        } else {
            $toUpdate = @()
        }

        foreach ($u in $toUpdate) {
            Write-Info "  更新: $($u.Slug) [$($u.Branch)] ..."
            try {
                $pullOutput = cmd /c "git -C `"$($u.Path)`" pull origin $($u.Branch) 2>&1"
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "    $($u.Slug) 更新完成"
                } else {
                    Write-Warn "    $($u.Slug) 更新失败: $pullOutput"
                }
            } catch {
                Write-Warn "    $($u.Slug) 更新异常: $_"
            }
        }

        if ($toUpdate.Count -eq 0 -and $choice) {
            Write-Info "  未选择任何仓库，跳过更新"
        }
    } elseif ($errors.Count -gt 0 -and $current.Count -eq 0) {
        Write-Warn "  所有仓库均不可达，无法检查更新"
    } else {
        Write-Success "  所有仓库均已是最新"
    }

    Write-Info ""
}

# ============================================================
# Phase 8: 刷新依赖图
# ============================================================

function Invoke-Phase8-RefreshDependencyGraph {
    Write-Banner "Phase 8: 刷新依赖图 (dependency-graph.json)"

    $reposPath = Join-Path $script:RootDir ".claude\repos.json"
    $depGraphPath = Join-Path $script:RootDir ".claude\dependency-graph.json"
    $depGraphTmp = $depGraphPath + ".tmp"
    $cachePath = $depGraphPath + ".cache"

    if (-not (Test-Path $reposPath)) {
        Write-Warn "repos.json 不存在，请先运行 [3] 管理仓库配置"
        return
    }

    $reposConfig = $null
    try {
        $reposConfig = Get-Content $reposPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Warn "repos.json 解析失败"
        return
    }

    if (-not $reposConfig.repos) {
        Write-Warn "repos.json 中无仓库"
        return
    }

    # 过滤已启用仓库
    $enabledRepos = @()
    $props = $reposConfig.repos.PSObject.Properties
    foreach ($prop in $props) {
        $enable = if ($null -ne $prop.Value.enable) { [bool]$prop.Value.enable } else { $true }
        if ($enable) { $enabledRepos += $prop.Name }
    }

    if ($enabledRepos.Count -eq 0) {
        Write-Warn "无已启用仓库，无法生成依赖图"
        return
    }

    Write-Info "已启用仓库: $($enabledRepos -join ', ')"

    # 加载 SHA 缓存和数据缓存
    $shaCache = @{}
    $dataCache = @{}
    if (Test-Path $depGraphPath) {
        try {
            $existingGraph = Get-Content $depGraphPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($existingGraph.repoHeadShas) {
                $existingGraph.repoHeadShas.PSObject.Properties | ForEach-Object {
                    $shaCache[$_.Name] = $_.Value
                }
            }
        } catch { }
    }
    if (Test-Path $cachePath) {
        try {
            $oldCache = Get-Content $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $oldCache.PSObject.Properties | ForEach-Object {
                $dataCache[$_.Name] = @{
                    sha          = $_.Value.sha
                    artifactId   = $_.Value.artifactId
                    version      = $_.Value.version
                    dependencies = $_.Value.dependencies
                }
            }
        } catch { }
    }

    # 导出映射：artifactId → { repo, version }
    $exportMap = @{}
    # 消费声明：repo → [ { artifact, version, full } ]
    $consumedMap = @{}
    # 新数据缓存
    $newData = @{}

    $parsedCount = 0
    $cachedCount = 0

    foreach ($slug in $enabledRepos) {
        $prop = $props | Where-Object { $_.Name -eq $slug }
        $localPath = if ($prop.Value.local) { $prop.Value.local.path } else { $null }

        # 获取当前 HEAD SHA
        $sha = $null
        if ($localPath -and (Test-Path (Join-Path $localPath ".git"))) {
            try {
                $sha = (git -C $localPath rev-parse HEAD 2>$null).Trim()
            } catch { }
        }

        # SHA 缓存检查
        $cached = $dataCache[$slug]
        if ($cached -and $cached.sha -and $sha -and $cached.sha -eq $sha) {
            $cachedCount++
            Write-Info "  $slug — SHA 未变，复用缓存"
            if ($cached.artifactId) {
                $exportMap[$cached.artifactId] = @{ repo = $slug; version = $cached.version }
            }
            if ($cached.dependencies) {
                $consumedMap[$slug] = $cached.dependencies
            }
            $newData[$slug] = $cached
            continue
        }

        # SHA 变更或无缓存 → 重新解析
        $parsedCount++
        Write-Info "  解析 $slug ..."

        $artifactId = $null
        $exportVersion = $null
        $deps = @()

        # 读取 publish.json（结构: { "modules": [{ "artifactId", "version" }] }）
        $publishPath = if ($localPath) { Join-Path $localPath "publish.json" } else { $null }
        if ($publishPath -and (Test-Path $publishPath)) {
            try {
                $publish = Get-Content $publishPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($publish.modules) {
                    $mods = if ($publish.modules -is [array]) { $publish.modules } else { @($publish.modules) }
                    foreach ($mod in $mods) {
                        if ($mod.artifactId) {
                            $exportMap[$mod.artifactId] = @{ repo = $slug; version = $mod.version }
                        }
                    }
                    # 取第一个 module 作为该仓库的主要导出标识
                    $firstMod = $mods[0]
                    $artifactId = $firstMod.artifactId
                    $exportVersion = if ($firstMod.version) { $firstMod.version } else { "0.0.0" }
                    Write-Success "    publish.json → $($mods.Count) module(s), 主要: $artifactId`:$exportVersion"
                }
            } catch {
                Write-Warn "    publish.json 解析失败"
            }
        }

        # ── 通用版本解析 ──
        # Step 0: 扫描仓库所有 .kt / .kts 文件，提取版本常量定义
        #     (val | var | const val) <任意名> = "<版本号>"
        #     不限文件名、不限变量名、不限是否在 buildSrc
        $globalVars = @{}
        if ($localPath -and (Test-Path $localPath)) {
            try {
                $allKtFiles = Get-ChildItem -Path $localPath -Recurse -Include "*.kt","*.kts" -ErrorAction SilentlyContinue `
                    | Where-Object { $_.FullName -notmatch '\\build\\' }
                foreach ($kf in $allKtFiles) {
                    $ktContent = Get-Content $kf.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                    if (-not $ktContent) { continue }
                    # 提取所有 val / var / const val name = "digit..."
                    $vmList = [regex]::Matches($ktContent, '(?:const\s+val|val|var)\s+(\w+)\s*=\s*"([0-9][0-9.]*)"')
                    foreach ($vm in $vmList) {
                        $vName = $vm.Groups[1].Value
                        $vVal  = $vm.Groups[2].Value
                        # 同时注册短名和可能的完全限定名，供后续 ${xxx} 和 ${Obj.xxx} 引用查找
                        if (-not $globalVars.ContainsKey($vName)) { $globalVars[$vName] = $vVal }
                    }
                }
            } catch { }
        }

        # Step 1: 递归读取所有 build.gradle.kts，匹配 com.wonder:* 依赖
        if ($localPath -and (Test-Path $localPath)) {
            try {
                $gradleFiles = Get-ChildItem -Path $localPath -Recurse -Filter "build.gradle.kts" -ErrorAction SilentlyContinue `
                    | Where-Object { $_.FullName -notmatch '\\build\\' }
                $seenDeps = @{}
                foreach ($gradleFile in $gradleFiles) {
                    $gradleContent = Get-Content $gradleFile.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                    if (-not $gradleContent) { continue }
                    # 匹配: com.wonder:artifact:<字面量版本 或 ${任意引用}>
                    $matchList = [regex]::Matches($gradleContent, 'com\.wonder:([a-zA-Z0-9_-]+):(?:([0-9][0-9.]*)|\$\{([^}]+)\})')
                    foreach ($m in $matchList) {
                        $depArtifact = $m.Groups[1].Value
                        $depVersion  = $null
                        if ($m.Groups[2].Success) {
                            # 字面量版本: 1.2.3
                            $depVersion = $m.Groups[2].Value
                        } elseif ($m.Groups[3].Success) {
                            # 变量引用: ${xxx} 或 ${Obj.xxx}
                            $ref = $m.Groups[3].Value
                            # 查全局变量表——先按完整引用查，再按最后一段查
                            if ($globalVars.ContainsKey($ref)) {
                                $depVersion = $globalVars[$ref]
                            } else {
                                $lastPart = ($ref -split '\.')[-1]
                                if ($globalVars.ContainsKey($lastPart)) {
                                    $depVersion = $globalVars[$lastPart]
                                }
                            }
                        }
                        if ($depArtifact -eq "wonder-dependencies") { continue }
                        # 版本解析失败 → 用 "unknown"，边依然建立
                        if (-not $depVersion) { $depVersion = "unknown" }
                        $key = "$depArtifact`:$depVersion"
                        if (-not $seenDeps.ContainsKey($key)) {
                            $seenDeps[$key] = $true
                            $deps += @{ artifact = $depArtifact; version = $depVersion; full = "$depArtifact`:$depVersion" }
                        }
                    }
                }
                if ($deps.Count -gt 0) {
                    Write-Success "    build.gradle.kts → $($deps.Count) 个依赖 (去重)"
                }
            } catch {
                Write-Warn "    build.gradle.kts 解析失败: $_"
            }
        }

        # 记录
        if ($artifactId) {
            $exportMap[$artifactId] = @{ repo = $slug; version = $exportVersion }
        }
        $consumedMap[$slug] = $deps

        $newData[$slug] = @{
            sha          = $sha
            artifactId   = $artifactId
            version      = $exportVersion
            dependencies = $deps
        }
    }

    Write-Info "解析完成: $parsedCount 个仓库重新解析, $cachedCount 个使用缓存"

    # --- 跨仓匹配 ---
    $edges = @()
    $unmatched = @()
    $seenEdgeKeys = @{}

    function Compare-Version($v1, $v2) {
        $parts1 = $v1 -split '\.'
        $parts2 = $v2 -split '\.'
        $maxLen = [Math]::Max($parts1.Count, $parts2.Count)
        for ($i = 0; $i -lt $maxLen; $i++) {
            $p1 = if ($i -lt $parts1.Count) { [int]$parts1[$i] } else { 0 }
            $p2 = if ($i -lt $parts2.Count) { [int]$parts2[$i] } else { 0 }
            if ($p1 -lt $p2) { return -1 }
            if ($p1 -gt $p2) { return 1 }
        }
        return 0
    }

    foreach ($slug in $enabledRepos) {
        $deps = $consumedMap[$slug]
        if (-not $deps) { continue }

        foreach ($dep in $deps) {
            $depArtifact = $dep.artifact
            $depVersion = $dep.version
            $depFull = $dep.full

            $export = $exportMap[$depArtifact]
            if ($export -and $export.repo -ne $slug) {
                # 跨仓匹配命中
                if ($depVersion -eq "unknown" -or $export.version -eq "unknown") {
                    $versionMatch = "unknown"
                } else {
                    $vc = Compare-Version $depVersion $export.version
                    $versionMatch = if ($vc -eq 0) { "exact" } elseif ($vc -lt 0) { "behind" } else { "ahead" }
                }

                $edgeKey = "$slug|$($export.repo)|$depArtifact"
                if (-not $seenEdgeKeys.ContainsKey($edgeKey)) {
                    $seenEdgeKeys[$edgeKey] = $true
                    $edges += [PSCustomObject]@{
                        fromRepo        = $slug
                        toRepo          = $export.repo
                        viaArtifact     = $depArtifact
                        versionConsumed = $depVersion
                        versionExported = $export.version
                        versionMatch    = $versionMatch
                        relationship    = "api-contract"
                        source          = "auto"
                    }
                    Write-Success "  匹配: $slug → $($export.repo) via $depArtifact ($versionMatch)"
                }
            } elseif (-not $export) {
                # 未匹配
                $likelyMissingRepo = $null
                if ($depArtifact -match "^(.+)-service-interface$") { $likelyMissingRepo = $Matches[1] }
                elseif ($depArtifact -match "^(.+)-client$") { $likelyMissingRepo = $Matches[1] }
                elseif ($depArtifact -match "^(.+)-api$") { $likelyMissingRepo = $Matches[1] }

                $unmatched += [PSCustomObject]@{
                    repo              = $slug
                    artifact          = $depFull
                    likelyMissingRepo = $likelyMissingRepo
                    likelyThirdParty  = $false
                }
                Write-Info "  未匹配: $slug — $depFull (可能缺失: $likelyMissingRepo)"
            }
        }
    }

    # --- 预计算 reverseEdges ---
    $reverseEdges = @{}
    foreach ($edge in $edges) {
        $toRepo = $edge.toRepo
        if (-not $reverseEdges.ContainsKey($toRepo)) {
            $reverseEdges[$toRepo] = @()
        }
        $reverseEdges[$toRepo] += @{ fromRepo = $edge.fromRepo; viaArtifact = $edge.viaArtifact }
    }

    # --- DFS 循环检测（使用 ArrayList 正确实现栈 Pop）---
    $cyclesDetected = $false
    $adjList = @{}
    foreach ($edge in $edges) {
        if (-not $adjList.ContainsKey($edge.fromRepo)) { $adjList[$edge.fromRepo] = @() }
        $adjList[$edge.fromRepo] += $edge.toRepo
    }

    $whiteSet = @{}
    $graySet = @{}
    $blackSet = @{}
    foreach ($slug in $enabledRepos) { $whiteSet[$slug] = $true }

    foreach ($startNode in $enabledRepos) {
        if (-not $whiteSet.ContainsKey($startNode)) { continue }
        $stack = New-Object System.Collections.ArrayList
        [void]$stack.Add(@{ node = $startNode; iter = $null })

        while ($stack.Count -gt 0) {
            $top = $stack[$stack.Count - 1]
            $node = $top.node

            if ($null -eq $top.iter) {
                $whiteSet.Remove($node)
                $graySet[$node] = $true
                $neighbors = $adjList[$node]
                $top.iter = if ($neighbors) { 0 } else { -1 }
            }

            if ($top.iter -ge 0) {
                $neighbors = $adjList[$node]
                if ($top.iter -lt $neighbors.Count) {
                    $n = $neighbors[$top.iter]
                    $top.iter++

                    if ($graySet.ContainsKey($n)) {
                        $cyclesDetected = $true
                        break
                    }
                    if ($whiteSet.ContainsKey($n)) {
                        [void]$stack.Add(@{ node = $n; iter = $null })
                    }
                    continue
                }
            }

            # 节点处理完毕 — ArrayList.RemoveAt 正确弹出
            $stack.RemoveAt($stack.Count - 1)
            $graySet.Remove($node)
            $blackSet[$node] = $true
        }

        if ($cyclesDetected) { break }
    }

    # --- repoHeadShas ---
    $repoHeadShas = @{}
    foreach ($slug in $enabledRepos) {
        $nd = $newData[$slug]
        $repoHeadShas[$slug] = if ($nd) { $nd.sha } else { $null }
    }

    # --- 构建依赖图 ---
    $depGraph = [PSCustomObject]@{
        schemaVersion  = "1.0"
        generatedAt    = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
        enabledRepos   = $enabledRepos
        repoHeadShas   = $repoHeadShas
        edges          = $edges
        reverseEdges   = $reverseEdges
        unmatched      = $unmatched
        cyclesDetected = $cyclesDetected
    }

    # --- 原子写入 ---
    Write-JsonFile -Object $depGraph -Path $depGraphTmp -Depth 10
    if (Test-Path $depGraphPath) { Remove-Item $depGraphPath -Force }
    Move-Item -Path $depGraphTmp -Destination $depGraphPath -Force

    # --- 写入数据缓存 ---
    $cacheObj = @{}
    foreach ($kv in $newData.GetEnumerator()) {
        $cacheObj[$kv.Key] = $kv.Value
    }
    Write-JsonFile -Object $cacheObj -Path $cachePath -Depth 5 -Compress

    Write-Success "依赖图已写入: .claude/dependency-graph.json"
    Write-Info "  edges: $($edges.Count) 条"
    Write-Info "  unmatched: $($unmatched.Count) 条"
    Write-Info "  cyclesDetected: $cyclesDetected"
    Write-Info "  已解析: $parsedCount | 缓存命中: $cachedCount"
    Write-Info ""
}

# ============================================================
# Main
# ============================================================

function Main {
    Write-Host "`n  " -ForegroundColor Cyan
    Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║              dm-seek(马冬梅计划)                   ║" -ForegroundColor Cyan
    Write-Host "  ║            Windows 一键初始化脚本                   ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    Write-Info "运行目录: $script:RootDir"
    Write-Info ""

    # --- 命令行参数：-Auto 全量执行（兼容旧用法）---
    if ($Auto) {
        Write-Info "全量执行模式：依次运行 Phase 1-6..."
        $env = Invoke-Phase1
        $auth = Invoke-Phase2 $env
        $repos = Invoke-Phase3 $env $auth
        Invoke-Phase4 $repos
        Invoke-Phase5 $auth
        Invoke-Phase6 $env $auth $repos
        Read-Host "按回车键退出"
        return
    }

    # --- 命令行参数：-Phase N 直接跳转 ---
    if ($Phase) {
        $env = $null; $auth = $null; $repos = $null
        switch ($Phase) {
            "1" { $script:EnvState = Invoke-Phase1 }
            "2" { $script:AuthState = Invoke-Phase2; if ($script:AuthState.ModeChanged) { Invoke-Phase5 $script:AuthState } }
            "3" { Invoke-Phase3 }
            "4" { Invoke-Phase4 }
            "5" { Invoke-Phase5 }
            "6" { Invoke-Phase6 }
            "7" { Invoke-UpdateCheck }
            "8" { Invoke-Phase8-RefreshDependencyGraph }
            default { Write-ErrorMsg "无效 Phase: $Phase（有效值: 1-8）" }
        }
        Read-Host "按回车键退出"
        return
    }

    # --- 交互菜单模式（默认）---
    Invoke-AutoScan  # 启动时自动扫描 dm-repos/ 和 dm-kbs/
    $cachedStatus = $null; $cacheTime = [DateTime]::MinValue
    do {
        if (((Get-Date) - $cacheTime).TotalSeconds -gt 10) { $cachedStatus = Get-InitStatus; $cacheTime = Get-Date }; $status = $cachedStatus
        Show-Status $status
        $choice = Show-MainMenu $status

        switch ($choice) {
            "1" {
                $script:EnvState = Invoke-Phase1
            }
            "2" {
                $script:AuthState = Invoke-Phase2 $script:EnvState
                # Phase 2 切换认证模式 → 自动写入 .mcp.json
                if ($script:AuthState.ModeChanged -and $script:AuthState.Mode -ne "none") {
                    Write-Info ""
                    Write-Warn "认证模式已变更，自动更新 .mcp.json..."
                    Invoke-Phase5 $script:AuthState
                }
            }
            "3" {
                $script:ReposState = Invoke-Phase3 $script:EnvState $script:AuthState
            }
            "4" {
                Invoke-Phase4 $script:ReposState
            }
            "5" {
                Invoke-Phase5 $script:AuthState
            }
            "6" {
                Invoke-Phase6 $script:EnvState $script:AuthState $script:ReposState
            }
            "7" {
                Invoke-UpdateCheck
            }
            "8" {
                Invoke-Phase8-RefreshDependencyGraph
            }
            "0" {
                Write-Info "退出。"
                break
            }
            default {
                if ($choice) {
                    Write-Warn "无效选择: $choice"
                }
            }
        }
    } while ($true)
}

try {
    Main
} catch {
    Write-Host "`n脚本异常终止: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
} finally {
    Read-Host "`n按回车键退出"
}
