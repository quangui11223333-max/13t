# setup-wsl.ps1 -- OPTIONAL. Install WSL2 + Ubuntu for OnePlus 13T kernel builds.
#
# NOTE: If you already have a real Linux machine, skip this file entirely and use
#       scripts/bootstrap-linux.sh there instead (much faster, no 8 GB RAM ceiling).
#
# This file is intentionally ASCII-only: Windows PowerShell 5.1 reads BOM-less .ps1
# as ANSI/GBK, and non-ASCII comments break the parser (that is what happened before).
#
# Run in an elevated PowerShell:
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   .\setup-wsl.ps1 -MoveDistroTo D:\WSL
#
# Host facts measured on this box: Win11 26H2 build 26340, VT-x enabled in BIOS,
# WSL + VirtualMachinePlatform currently Disabled -> a reboot is required.

#Requires -RunAsAdministrator
param(
  [string]$Distro = 'Ubuntu-24.04',
  [string]$MoveDistroTo = '',
  [int]$MemoryGB = 5,
  [int]$SwapGB = 8,
  [int]$Processors = 4
)

$ErrorActionPreference = 'Stop'
function Step($m) { Write-Host "`n=== $m" -ForegroundColor Cyan }

Step "1/5 enable WSL and VirtualMachinePlatform (reboot required)"
$f1 = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
if ($f1.State -ne 'Enabled') {
  Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart | Out-Null
  Write-Host "  WSL feature enabled"
} else { Write-Host "  WSL feature already enabled" }

$f2 = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
if ($f2.State -ne 'Enabled') {
  Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart | Out-Null
  Write-Host "  VirtualMachinePlatform enabled"
} else { Write-Host "  VirtualMachinePlatform already enabled" }

Step "2/5 update WSL kernel, default version 2"
wsl.exe --update
wsl.exe --set-default-version 2

Step "3/5 install distro $Distro"
$installed = (& wsl.exe -l -q) -replace "`0", ''
if ($installed -match [regex]::Escape($Distro)) {
  Write-Host "  $Distro already installed"
} else {
  wsl.exe --install -d $Distro --no-launch
}

Step "4/5 write %USERPROFILE%\.wslconfig ($MemoryGB GB / swap $SwapGB GB / $Processors cores)"
$cfgPath = Join-Path $env:USERPROFILE '.wslconfig'
$cfg = @"
[wsl2]
memory=${MemoryGB}GB
swap=${SwapGB}GB
processors=$Processors
autoMemoryReclaim=disabled

[experimental]
sparseVhd=true
"@
if (Test-Path $cfgPath) {
  Copy-Item $cfgPath ($cfgPath + '.bak') -Force
  Write-Host "  backup written: $cfgPath.bak"
}
Set-Content -Path $cfgPath -Value $cfg -Encoding utf8
Write-Host "  written: $cfgPath"

Step "5/5 move distro VHD (optional)"
if ($MoveDistroTo) {
  New-Item -ItemType Directory -Force -Path $MoveDistroTo | Out-Null
  try {
    wsl.exe --manage $Distro --move $MoveDistroTo
    Write-Host "  moved to $MoveDistroTo"
  } catch {
    Write-Host ("  move failed: " + $_.Exception.Message) -ForegroundColor Yellow
    Write-Host "  fallback: wsl --export $Distro D:\wsl-$Distro.tar ; wsl --unregister $Distro ; wsl --import ..."
  }
} else {
  Write-Host "  skipped (distro stays on C:, build artifacts may eat 30-60 GB)"
}

Write-Host @"

==========================================================
NEXT
==========================================================
1) Reboot Windows (the two features above need it)
2) Open the Ubuntu app once, set user/password, then:

   cd /path/to/kernels/oneplus13t/scripts && bash bootstrap-linux.sh

   (copy the scripts dir onto ext4 first, e.g. cp -r /mnt/c/.../scripts ~/13t-scripts)
==========================================================
"@ -ForegroundColor Green
