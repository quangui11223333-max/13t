$ErrorActionPreference = 'Stop'
# Push the local scaffold repo to GitHub using a PAT, without storing the token.
#   .\push-repo.ps1 -Token 'github_pat_xxx'
#   .\push-repo.ps1 -Token 'github_pat_xxx' -Branch main
# ASCII-only on purpose: Windows PowerShell 5.1 reads BOM-less non-ASCII as GBK.
param(
    [Parameter(Mandatory = $true)][string]$Token,
    [string]$Repo = 'https://github.com/quangui11223333-max/13t.git',
    [string]$Branch = 'main'
)

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
    # scrub the token out of anything git echoes back
    $_.ToString().Replace($Token, '***')
}
$code = $LASTEXITCODE
if ($code -ne 0) {
    Write-Host "== push FAILED (exit $code)"
    Write-Host "   check: token has 'Contents: Read and write' on this repo; repo is empty or already has this branch"
    exit $code
}

Write-Host "== local branch tracking set"
& $git -C $root remote remove origin 2>$null | Out-Null
& $git -C $root remote add origin $Repo
& $git -C $root branch --set-upstream-to="origin/$Branch" 2>$null | Out-Null

Write-Host "== done: $Repo/tree/$Branch"
Write-Host "   revoke the token when you are done with it"
