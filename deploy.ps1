<#
.SYNOPSIS
    Builds and deploys the site from this machine, without GitHub.

.DESCRIPTION
    Does exactly what .github/workflows/deploy.yml does, so the local and CI
    paths cannot drift: build, sanity-check the output, then rclone sync to the
    server over SFTP.

    Use this when GitHub Actions is unavailable, or when you want to watch a
    deploy happen.

.PARAMETER DryRun
    Show what would change on the server without changing anything.

.EXAMPLE
    ./deploy.ps1 -DryRun
    ./deploy.ps1
#>
[CmdletBinding()]
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

Write-Host '==> Building site' -ForegroundColor Cyan
dotnet run --configuration Release
if ($LASTEXITCODE -ne 0) { throw "Build failed with exit code $LASTEXITCODE" }

Write-Host '==> Checking output' -ForegroundColor Cyan
if (-not (Test-Path 'output/index.html')) {
    throw 'No output/index.html was produced; refusing to deploy.'
}
$pages = @(Get-ChildItem -Path 'output' -Filter '*.html' -Recurse -File).Count
Write-Host "    $pages HTML pages"
if ($pages -lt 20) {
    throw "Only $pages pages produced; that looks like a broken build. Refusing to deploy."
}

# Pin the server's host key. Without this rclone silently accepts any key,
# which is what the old update.ps1 did.
$knownHosts = Join-Path $HOME '.ssh/known_hosts'
if (-not (Test-Path $knownHosts)) {
    throw "No known_hosts at $knownHosts; refusing to deploy without host key validation."
}

$rcloneArgs = @(
    'sync', 'output', 'interfree:stuff/output'
    '--sftp-known-hosts-file', $knownHosts
    '--checksum'
    '--max-delete', '50'   # a bad build should not be able to gut the live site
    '--stats-one-line'
    '--verbose'
)
if ($DryRun) { $rcloneArgs += '--dry-run' }

Write-Host "==> Syncing to interfree.ca$(if ($DryRun) { ' (dry run)' })" -ForegroundColor Cyan
rclone @rcloneArgs
if ($LASTEXITCODE -ne 0) { throw "rclone failed with exit code $LASTEXITCODE" }

Write-Host '==> Done' -ForegroundColor Green
