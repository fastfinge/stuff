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

# Build from scratch. Statiq leaves behind pages whose source file has since
# been deleted, and rclone sync would then push those stale pages live. CI
# never hits this because it builds from a fresh checkout; local builds do.
if (Test-Path 'output') {
    Write-Host '==> Clearing previous output' -ForegroundColor Cyan
    Remove-Item -LiteralPath 'output' -Recurse -Force
}

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

# Tell the WebSub hub the feeds changed, so subscribers hear about a new post in
# seconds rather than whenever they next poll. This has to come after the sync:
# the hub fetches the feed immediately, and would cache the old one otherwise.
# A hub having a bad day is not a reason to call a finished deploy a failure.
if (-not $DryRun) {
    $settings = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'settings.yml'))
    $hub = if ($settings -match '(?m)^WebSubHub:\s*(.+)$') { $Matches[1].Trim() } else { $null }
    $siteHost = if ($settings -match '(?m)^Host:\s*(.+)$') { $Matches[1].Trim() } else { $null }
    $scheme = if ($settings -match '(?m)^LinksUseHttps:\s*true') { 'https' } else { 'http' }

    if ($hub -and $siteHost) {
        Write-Host '==> Pinging the WebSub hub' -ForegroundColor Cyan
        # Only the two feeds that carry a rel=hub link; the hub verifies that.
        foreach ($feed in @('feed.rss', 'feed.atom')) {
            $topic = "${scheme}://${siteHost}/$feed"
            try {
                Invoke-WebRequest -Uri $hub -Method Post -TimeoutSec 30 `
                    -Body @{ 'hub.mode' = 'publish'; 'hub.url' = $topic } | Out-Null
                Write-Host "    published $topic"
            }
            catch {
                Write-Warning "WebSub ping for $topic failed: $($_.Exception.Message)"
            }
        }
    }
}

Write-Host '==> Done' -ForegroundColor Green
