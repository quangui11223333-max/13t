# deploy-to-linux.ps1 -- drive the OnePlus 13T kernel build on your LAN Linux box,
# straight from this Windows machine. No admin rights, no OpenSSH install:
# uses the portable PuTTY (plink/pscp) already downloaded in ..\tools\.
#
# ASCII-only on purpose: Windows PowerShell 5.1 mis-parses BOM-less non-ASCII .ps1 files.
#
# Examples
#   .\deploy-to-linux.ps1 -Target me@192.168.1.246 -Password 'secret' -Action bootstrap
#   .\deploy-to-linux.ps1 -Target me@192.168.1.246 -KeyFile C:\keys\linux.ppk -Action status
#   .\deploy-to-linux.ps1 -Target me@192.168.1.246 -KeyFile C:\keys\linux.ppk -Action build
#   .\deploy-to-linux.ps1 -Target me@10.0.0.5 -Port 2222 -Password 'x' -Action cmd -RemoteCommand "uname -a"
#
# Actions:
#   check     - connect, print host facts (distro / cores / ram / disk)
#   bootstrap - upload the setup bundle and run bootstrap-linux.sh (installs deps + assembles)
#   build     - start the baseline build in the background (nohup, logs to ~/work/13t/build.log)
#   status    - tail the build log + report artifacts
#   cmd       - run an arbitrary command (-RemoteCommand)

param(
  [Parameter(Mandatory=$true)][string]$Target,      # user@host
  [int]$Port = 22,
  [string]$Password,
  [string]$KeyFile,
  [ValidateSet('check','bootstrap','build','status','cmd')][string]$Action = 'check',
  [string]$RemoteCommand = '',
  [string]$WorkDir = '/home/$USER/work/13t',        # expanded remotely
  [string]$Zip = ''
)

$ErrorActionPreference = 'Stop'
$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$base   = Split-Path -Parent $here
$tools  = Join-Path $base 'tools'
$plink  = Join-Path $tools 'plink.exe'
$pscp   = Join-Path $tools 'pscp.exe'
$pskgen = Join-Path $tools 'puttygen.exe'

foreach ($exe in @($plink, $pscp)) {
  if (-not (Test-Path $exe)) { throw "missing $exe -- re-download PuTTY portable into $tools" }
}
if (-not $Zip) { $Zip = Join-Path $base 'oneplus13t-kernel-setup.tar.gz' }

function Build-Auth {
  $a = @('-P', "$Port")
  if ($KeyFile) {
    if (-not (Test-Path $KeyFile)) { throw "keyfile not found: $KeyFile" }
    $a += @('-i', $KeyFile)
  } elseif ($Password) {
    $a += @('-pw', $Password)
  } else {
    throw "need -Password or -KeyFile"
  }
  return $a
}

function Invoke-Plink {
  param([string]$Command, [switch]$Quiet)
  $auth = Build-Auth
  $args = @() + $auth + @($Target, $Command)
  $out = & $plink @args 2>&1
  $code = $LASTEXITCODE
  if ($code -ne 0) {
    $txt = ($out | Out-String)
    if ($txt -match 'host key|Host key|not cached') {
      Write-Host "== first contact: caching host key" -ForegroundColor Yellow
      $tmp = [System.IO.Path]::GetTempFileName()
      Set-Content -Path $tmp -Value 'y' -Encoding ascii -NoNewline
      cmd.exe /c "`"$plink`" $($args -join ' ') < `"$tmp`"" | Out-Null
      Remove-Item $tmp -Force
      $out = & $plink @args 2>&1
      $code = $LASTEXITCODE
    }
  }
  if (-not $Quiet) { $out }
  return $code
}

Write-Host "== target $Target : $Port  action=$Action" -ForegroundColor Cyan

switch ($Action) {

  'check' {
    $cmd = @'
echo "host : $(hostname)"
echo "os   : $(. /etc/os-release 2>/dev/null; echo $PRETTY_NAME)"
echo "krnl : $(uname -r) $(uname -m)"
echo "cpu  : $(nproc) threads"
echo "mem  : $(free -h | awk '/^Mem:/{print $2}')"
echo "home : $(df -h $HOME | awk 'NR==2{print $4" free of "$2" at "$6}')"
echo "py   : $(python3 -V 2>&1)"
echo "sshd : $(systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || echo n/a)"
echo "sudo : $(sudo -n true 2>/dev/null && echo passwordless || echo needs-password)"
'@
    $code = Invoke-Plink -Command $cmd
    if ($code -ne 0) { Write-Host "connect failed (exit $code)" -ForegroundColor Red }
  }

  'bootstrap' {
    if (-not (Test-Path $Zip)) { throw "bundle not found: $Zip" }
    Write-Host "== uploading $([math]::Round((Get-Item $Zip).Length/1KB,1)) KB bundle"
    $auth = Build-Auth
    & $pscp @($auth + @('-P', "$Port", $Zip, "${Target}:/tmp/13t-setup.tar.gz")) 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "pscp upload failed ($LASTEXITCODE)" }
    $cmd = @'
set -e
mkdir -p /tmp/13t-setup && cd /tmp/13t-setup
tar xzf /tmp/13t-setup.tar.gz
cd scripts
bash bootstrap-linux.sh 2>&1 | tee /tmp/13t-bootstrap.log
echo "---- bootstrap finished, log: /tmp/13t-bootstrap.log"
'@
    $code = Invoke-Plink -Command $cmd
    if ($code -ne 0) { Write-Host "bootstrap returned $code -- see /tmp/13t-bootstrap.log" -ForegroundColor Yellow }
  }

  'build' {
    $cmd = @"
set -e
TREE="\$HOME/work/13t/oneplus13t-kernel"
[ -d "\$TREE" ] || { echo "tree missing: run -Action bootstrap first"; exit 2; }
cd "\$TREE"
LOG="\$HOME/work/13t/build.log"
: > "\$LOG"
nohup bash "\$HOME/work/13t/build.sh" > "\$LOG" 2>&1 &
echo "started pid \$! -- log: \$LOG"
sleep 3
tail -n 5 "\$LOG" || true
"@
    Invoke-Plink -Command $cmd | Out-Null
  }

  'status' {
    $cmd = @'
TREE="$HOME/work/13t/oneplus13t-kernel"
echo "---- running build processes:"
pgrep -af 'oplus_build_kernel|prepare_vendor|bazel' | head -5 || echo "  (none)"
echo "---- log tail:"
tail -n 25 "$HOME/work/13t/build.log" 2>/dev/null || echo "  (no log yet)"
echo "---- artifacts:"
ls -lh "$TREE/out/msm-kernel/sun_perf/dist/" 2>/dev/null | head -12 || echo "  (nothing yet)"
echo "---- load/disk:"
uptime; df -h "$HOME" | awk 'NR==2{print "  "$4" free"}'
'@
    Invoke-Plink -Command $cmd | Out-Null
  }

  'cmd' {
    if (-not $RemoteCommand) { throw "use -Action cmd -RemoteCommand 'uname -a'" }
    Invoke-Plink -Command $RemoteCommand | Out-Null
  }
}

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
