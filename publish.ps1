<#
.SYNOPSIS
    Runs the whole publish sequence from this machine, without GitHub.

.DESCRIPTION
    The same job .github/workflows/deploy.yml does, in the same order and for
    the same reasons: deploy, announce, deploy again, send webmentions.

        1. ./deploy.ps1            build, sanity check, sync, ping the hub
        2. ./announce.ps1 -Publish only after the deploy, because announce.ps1
                                   refuses to post a URL that is not live yet
                                   and a fediverse post cannot be edited later
        3. ./deploy.ps1            again, but only if something was announced:
                                   the pages built in step 1 had no Fedi: value,
                                   so they went out without their comment
                                   widgets and u-syndication link
        4. ./webmention.ps1 -Send  last, because a receiver fetches the source
                                   URL to check the link is really there

    Use this when GitHub Actions is unavailable. Steps 2 and 4 both write state
    into the repo -- the Fedi: keys and webmentions-sent.json -- and that state
    is the only record that the work has been done. Commit it, or the next CI
    run posts a duplicate announcement and mentions the same links again. Pass
    -Commit to have this script commit it for you.

.PARAMETER DryRun
    Show what every step would do and change nothing: no files on the server, no
    fediverse post, no webmentions, no commit.

.PARAMETER Commit
    Commit the Fedi: keys and webmentions-sent.json when finished. Commits
    locally only -- pushing is left to you, because a push starts a CI run.

.EXAMPLE
    ./publish.ps1 -DryRun    # walk through it, changing nothing
    ./publish.ps1            # publish for real
    ./publish.ps1 -Commit    # ...and commit what it wrote back
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Commit
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
# Set-Location does not move the .NET process working directory, so a relative
# path passed to [System.IO.File] would resolve against wherever the shell was
# started. Keep the two in step.
[Environment]::CurrentDirectory = $PSScriptRoot

$deploy     = Join-Path $PSScriptRoot 'deploy.ps1'
$announce   = Join-Path $PSScriptRoot 'announce.ps1'
$webmention = Join-Path $PSScriptRoot 'webmention.ps1'

function Write-Step {
    param([string]$Message)
    Write-Host ''
    Write-Host "### $Message" -ForegroundColor Magenta
}

# The patch for a set of paths, as one string. Comparing this before and after
# announce.ps1 is how we tell whether it actually wrote anything, without
# mistaking edits that were already sitting in the working tree for its work.
function Get-DiffState {
    param([string[]]$Paths)
    $patch = git diff -- @Paths 2>$null
    return ($patch | Out-String)
}

if ($DryRun) {
    Write-Host 'DRY RUN -- nothing will be deployed, posted, sent or committed.' -ForegroundColor Yellow
}

# --- Preflight -----------------------------------------------------------
# Cheap checks first, so a missing tool is not discovered after the site has
# already been half-published.

foreach ($tool in 'dotnet', 'rclone', 'git') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool is not on PATH."
    }
}

# Mirrors the CI step: no token is not an error, it just means there is nothing
# to announce with. Better to say so now than to fail between two deploys.
$canAnnounce = [bool]$env:FEDI_TOKEN
if (-not $canAnnounce) {
    Write-Warning 'FEDI_TOKEN is not set; the announce step will be skipped.'
}

# --- 1. Deploy -----------------------------------------------------------

Write-Step 'Step 1/4: deploy'
if ($DryRun) { & $deploy -DryRun } else { & $deploy }

# --- 2. Announce ---------------------------------------------------------

Write-Step 'Step 2/4: announce'
$announced = $false

if (-not $canAnnounce -and -not $DryRun) {
    Write-Host 'Skipped: no FEDI_TOKEN.' -ForegroundColor DarkGray
}
elseif ($DryRun) {
    & $announce
}
else {
    $before = Get-DiffState 'input/posts'
    & $announce -Publish
    $announced = (Get-DiffState 'input/posts') -ne $before
}

# --- 3. Redeploy ---------------------------------------------------------

Write-Step 'Step 3/4: redeploy'
if ($announced) {
    # The just-published pages went out without their comment widgets and
    # u-syndication link, because the Fedi: value did not exist when they were
    # built. This is the build that gives them one.
    & $deploy
}
else {
    Write-Host 'Skipped: nothing was announced, so nothing needs rebuilding.' -ForegroundColor DarkGray
}

# --- 4. Webmentions ------------------------------------------------------

Write-Step 'Step 4/4: webmentions'
# Reads output/, which the deploy above has just rebuilt, and needs the post to
# be live: a receiver fetches the source URL to verify the link exists.
if ($DryRun) { & $webmention } else { & $webmention -Send }

# --- What was written back -----------------------------------------------

Write-Step 'Done'

if ($DryRun) {
    Write-Host 'Dry run finished. Nothing was changed.' -ForegroundColor Green
    return
}

# Both of these are records that something irreversible has already happened.
# Losing them is not a tidiness problem: an uncommitted Fedi: key means the next
# CI run announces the post a second time, and an uncommitted
# webmentions-sent.json means it mentions every one of those links again.
$dirty = @(git status --porcelain -- input/posts webmentions-sent.json |
    ForEach-Object { $_.Substring(3) } |
    Where-Object { $_ })

if (-not $dirty) {
    Write-Host 'Published. Nothing was written back, so there is nothing to commit.' -ForegroundColor Green
    return
}

Write-Host 'Published. These files record what just happened and must be committed:' -ForegroundColor Yellow
$dirty | ForEach-Object { Write-Host "    $_" }

if (-not $Commit) {
    Write-Host ''
    Write-Host 'Commit them with:' -ForegroundColor Yellow
    Write-Host "    git add -- input/posts webmentions-sent.json"
    Write-Host "    git commit -m 'Record what publish.ps1 sent [skip ci]'"
    return
}

Write-Host ''
Write-Host '==> Committing' -ForegroundColor Cyan
git add -- input/posts webmentions-sent.json
if ($LASTEXITCODE -ne 0) { throw "git add failed with exit code $LASTEXITCODE" }
# [skip ci] because this deploy has already happened; without it, pushing would
# start a CI run that rebuilds and redeploys the identical site.
git commit -m 'Record what publish.ps1 sent [skip ci]'
if ($LASTEXITCODE -ne 0) { throw "git commit failed with exit code $LASTEXITCODE" }

Write-Host ''
Write-Host 'Committed, but not pushed -- a push starts a CI run. Push when ready:' -ForegroundColor Yellow
Write-Host '    git push origin main'
