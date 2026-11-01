# Push the local scaffold repo to GitHub using a PAT, without storing the token.
#   .\push-repo.ps1 -Token 'github_pat_xxx'
#   .\push-repo.ps1 -Token 'github_pat_xxx' -Branch main
# ASCII-only on purpose: Windows PowerShell 5.1 reads BOM-less non-ASCII as GBK.
#
# NOTE: param() must be the first executable statement in a PowerShell script -
# do not put $ErrorActionPreference or anything else above it, or the parser
# reports "InvalidLeftHandSide" for every parameter.
param(
    [Parameter(Mandatory = $true)][string]$Token,
    [string]$Repo = 'https://github.com/quangui11223333-max/13t.git',
    [string]$Branch = 'main'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot          # scripts\ -> kernels\oneplus13t
$git = Join-Path $root 'tools\MinGit\cmd\git.exe'
if (-not (Test-Path $git)) { throw "MinGit not found: $git" }
if (-not (Test-Path (Join-Path $root '.git'))) { throw "no .git in $root - run git init first" }

Write-Host "== repo : $root"
Write-Host "== head : $(& $git -C $root rev-parse --short HEAD)"
Write-Host "== files: $((& $git -C $root ls-files | Measure-Object).Count)"

$authUrl = $Repo -replace '^https://', ("https://x-access-token:" + $Token + "@")
$refspec = "HEAD:refs/heads/$Branch"

Write-Host "== pushing to $Branch ..."
& $git -C $root push --porcelain $authUrl $refspec 2>&1 | ForEach-Object {
    $_.ToString().Replace($Token, '***')      # never echo the token back
}
if ($LASTEXITCODE -ne 0) {
    Write-Host "== push FAILED (exit $LASTEXITCODE)"
    Write-Host "   check: token scope 'repo' + 'workflow'; branch exists / repo writable"
    exit $LASTEXITCODE
}

& $git -C $root remote remove origin 2>$null | Out-Null
& $git -C $root remote add origin $Repo
Write-Host "== done: $Repo/tree/$Branch"
Write-Host "   revoke the token when you are done with it"
