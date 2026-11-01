# fetch-deps.ps1 -- download the 35 OnePlus 13T kernel build deps on WINDOWS,
# for boxes whose GitHub access is broken (the Arch box times out on github:443).
# ASCII-only: Windows PowerShell 5.1 mis-parses BOM-less non-ASCII .ps1.
#
#   .\fetch-deps.ps1 -Dest D:\kernel-cache\oneplus13t\_dl -Reuse  C:\...\src\_dl
#   .\fetch-deps.ps1 -Dest D:\kernel-cache\oneplus13t\_dl -VerifyOnly
#
# Output filenames match assemble.py exactly: <name with / replaced by _>.tar.gz
# Strict size+sha256 only for source=release-mirror; GitHub /archive archives are
# non-deterministic, so those are checked by size drift + successful tar listing.

param(
  [string]$Deps = '',
  [Parameter(Mandatory=$true)][string]$Dest,
  [string]$Reuse = '',
  [switch]$VerifyOnly,
  [int]$Jobs = 3
)

$ErrorActionPreference = 'Stop'
if (-not $Deps) {
  $Deps = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'deps.json'
}
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
$list = Get-Content $Deps -Raw | ConvertFrom-Json

function Get-Sha256($p) { (Get-FileHash $p -Algorithm SHA256).Hash.ToLower() }

function Test-Tar($p) {
  # Windows ships bsdtar as tar.exe; -tzf returns 0 only if the gzip+tar is readable
  $null = & tar.exe -tzf $p 2>&1
  return ($LASTEXITCODE -eq 0)
}

function Test-Dep($dep, $file) {
  if (-not (Test-Path $file)) { return 'missing' }
  $len = (Get-Item $file).Length
  if ($dep.source -eq 'release-mirror') {
    if ($len -ne $dep.bytes) { return "size $len != $($dep.bytes)" }
    $h = Get-Sha256 $file
    if ($h -ne $dep.sha256) { return "sha256 $($h.Substring(0,12)) != $($dep.sha256.Substring(0,12))" }
    return 'ok'
  }
  if ($len -eq 0) { return 'empty' }
  if (-not (Test-Tar $file)) { return 'corrupt-archive' }
  return 'ok'
}

# stage: reuse previously downloaded archives whose names already match
if ($Reuse -and (Test-Path $Reuse)) {
  foreach ($dep in $list) {
    $fname = ($dep.name -replace '/', '_') + '.tar.gz'
    $src = Join-Path $Reuse $fname
    $dst = Join-Path $Dest $fname
    if ((Test-Path $src) -and -not (Test-Path $dst)) {
      Copy-Item $src $dst -Force
      Write-Host "reused $fname"
    }
  }
}

if ($VerifyOnly) {
  $bad = 0
  foreach ($dep in $list) {
    $fname = ($dep.name -replace '/', '_') + '.tar.gz'
    $st = Test-Dep $dep (Join-Path $Dest $fname)
    if ($st -ne 'ok') { $bad++; Write-Host ("  BAD  {0,-58} {1}" -f $dep.name, $st) }
  }
  Write-Host "verify: $($list.Count - $bad)/$($list.Count) ok"
  exit 0
}

$ok = 0; $skip = 0; $fail = @()
$sw = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($dep in $list) {
  $fname = ($dep.name -replace '/', '_') + '.tar.gz'
  $file = Join-Path $Dest $fname
  $st = Test-Dep $dep $file
  if ($st -eq 'ok') { $skip++; Write-Host ("  cached  {0,-56} {1,7:N1} MB" -f $dep.name, ((Get-Item $file).Length/1MB)); continue }

  $mb = [math]::Round($dep.bytes/1MB, 1)
  Write-Host ("  GET     {0,-56} {1,8:N1} MB" -f $dep.name, $mb)
  $tmp = "$file.part"
  $done = $false
  for ($try = 1; $try -le 3 -and -not $done; $try++) {
    & curl.exe -sS -L --retry 2 --retry-delay 2 --connect-timeout 20 --max-time 3600 -C - -o $tmp $dep.url
    $code = $LASTEXITCODE
    if (Test-Path $tmp) {
      Move-Item $tmp $file -Force
      $st2 = Test-Dep $dep $file
      if ($st2 -eq 'ok') { $done = $true; $ok++; Write-Host ("          ok  {0,8:N1} MB  ({1}s)" -f ((Get-Item $file).Length/1MB), [int]$sw.Elapsed.TotalSeconds) }
      else { Write-Host "          try$try bad: $st2 (curl=$code)"; Remove-Item $file -Force -ErrorAction SilentlyContinue }
    } else {
      Write-Host "          try$try no output (curl=$code)"
    }
    Start-Sleep -Seconds 2
  }
  if (-not $done) { $fail += $dep.name }
}

Write-Host ""
Write-Host ("DONE  ok={0} cached={1} failed={2}  elapsed={3} min  total={4:N1} GB" -f $ok, $skip, $fail.Count, [int]$sw.Elapsed.TotalMinutes, ((Get-ChildItem $Dest -File | Measure-Object Length -Sum).Sum/1GB))
if ($fail.Count) { Write-Host "FAILED:"; $fail | ForEach-Object { Write-Host "  $_" } }
