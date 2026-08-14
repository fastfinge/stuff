<#
.SYNOPSIS
    Announces posts on the social networks listed in their front matter.

.DESCRIPTION
    A post opts in by listing targets in its front matter:

        Announce: fedi
        # or
        Announce:
        - fedi
        - bluesky
        # or
        Announce: [fedi, bluesky]

    Each target records the resulting post URL under its own front matter key
    (fedi -> Fedi:), which is both what the comment widget reads and how this
    script knows the post has already been announced there. A target that
    already has its key is skipped, so re-running is safe.

    Dry run by default: it prints what it would post and changes nothing.
    Pass -Publish to actually post.

.PARAMETER Publish
    Actually post. Without this, nothing is sent and no file is modified.

.PARAMETER Target
    Only handle this one target (e.g. fedi), ignoring others listed in posts.

.PARAMETER SkipUrlCheck
    Do not verify that the post is already live before announcing it.

.EXAMPLE
    ./announce.ps1                  # show what would be posted
    ./announce.ps1 -Publish         # post it
#>
[CmdletBinding()]
param(
    [switch]$Publish,
    [string]$Target,
    [switch]$SkipUrlCheck,
    [string]$PostsPath = 'input/posts'
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

# --- Targets -------------------------------------------------------------
# To add a network later, add an entry here and implement its Post block.
# UrlKey is the front matter key holding the resulting URL.
$Targets = @{
    fedi = @{
        UrlKey   = 'Fedi'
        TokenVar = 'FEDI_TOKEN'
        Post     = {
            param($text)
            $instance = if ($env:FEDI_INSTANCE) { $env:FEDI_INSTANCE } else { 'https://fed.interfree.ca' }
            $body = @{ status = $text; visibility = 'public' } | ConvertTo-Json -Compress
            $response = Invoke-RestMethod -Method Post -Uri "$instance/api/v1/statuses" `
                -Headers @{ Authorization = "Bearer $env:FEDI_TOKEN" } `
                -ContentType 'application/json; charset=utf-8' `
                -Body ([System.Text.Encoding]::UTF8.GetBytes($body))
            if (-not $response.url) { throw 'The server response contained no url field.' }
            return $response.url
        }
    }
}

# --- Front matter --------------------------------------------------------

function Read-FrontMatter {
    param([string]$Path)

    $raw = [System.IO.File]::ReadAllText($Path)
    $newline = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
    $lines = $raw -split "`r?`n"

    $end = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^---\s*$') { $end = $i; break }
    }
    if ($end -lt 0) { return $null }   # no front matter; not a post we handle

    return [pscustomobject]@{
        Path    = $Path
        Lines   = $lines
        End     = $end
        Newline = $newline
    }
}

function Get-Scalar {
    param($Fm, [string]$Key)
    for ($i = 0; $i -lt $Fm.End; $i++) {
        if ($Fm.Lines[$i] -match "^$([regex]::Escape($Key)):\s*(.*)$") {
            return $Matches[1].Trim()
        }
    }
    return $null
}

function Test-HasKey {
    param($Fm, [string]$Key)
    for ($i = 0; $i -lt $Fm.End; $i++) {
        if ($Fm.Lines[$i] -match "^$([regex]::Escape($Key)):") { return $true }
    }
    return $false
}

# Accepts "Announce: fedi", "Announce: [fedi, bluesky]", or a YAML block list.
function Get-List {
    param($Fm, [string]$Key)

    for ($i = 0; $i -lt $Fm.End; $i++) {
        if ($Fm.Lines[$i] -notmatch "^$([regex]::Escape($Key)):\s*(.*)$") { continue }

        $inline = $Matches[1].Trim()
        if ($inline) {
            return ($inline.Trim('[', ']') -split ',' |
                ForEach-Object { $_.Trim().Trim('"', "'") } |
                Where-Object { $_ })
        }

        $items = @()
        for ($j = $i + 1; $j -lt $Fm.End; $j++) {
            if ($Fm.Lines[$j] -match '^\s*-\s*(.+)$') {
                $items += $Matches[1].Trim().Trim('"', "'")
            }
            elseif ($Fm.Lines[$j].Trim()) { break }
        }
        return $items
    }
    return @()
}

function Add-FrontMatterKey {
    param($Fm, [string]$Key, [string]$Value)

    $before = if ($Fm.End -gt 0) { $Fm.Lines[0..($Fm.End - 1)] } else { @() }
    $after  = $Fm.Lines[$Fm.End..($Fm.Lines.Count - 1)]
    $merged = @($before) + @("${Key}: $Value") + @($after)

    # UTF-8 with no BOM, matching the existing posts.
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Fm.Path, ($merged -join $Fm.Newline), $encoding)
}

# --- Site config ---------------------------------------------------------

$settings = [System.IO.File]::ReadAllText('settings.yml')
$host_ = if ($settings -match '(?m)^Host:\s*(.+)$') { $Matches[1].Trim() } else { throw 'No Host in settings.yml' }
$scheme = if ($settings -match '(?m)^LinksUseHttps:\s*true') { 'https' } else { 'http' }

function Get-PostUrl {
    param($Fm)
    $published = Get-Scalar $Fm 'Published'
    if (-not $published) { return $null }
    $date = [datetime]::Parse($published, [cultureinfo]::InvariantCulture)
    $slug = [System.IO.Path]::GetFileNameWithoutExtension($Fm.Path)
    # InvariantCulture matters: "/" in a format string is the culture's date
    # separator placeholder, which is not "/" everywhere.
    $datePath = $date.ToString('yyyy/MM/dd', [cultureinfo]::InvariantCulture)
    return "${scheme}://${host_}/$datePath/$slug.html"
}

# --- Main ----------------------------------------------------------------

if (-not $Publish) {
    Write-Host 'DRY RUN -- nothing will be posted. Pass -Publish to post for real.' -ForegroundColor Yellow
}

$posts = Get-ChildItem -Path $PostsPath -Filter '*.md' -Recurse -File
$pending = 0
$done = 0

foreach ($file in $posts) {
    $fm = Read-FrontMatter $file.FullName
    if (-not $fm) { continue }

    $wanted = Get-List $fm 'Announce'
    if (-not $wanted) { continue }
    if ($Target) { $wanted = $wanted | Where-Object { $_ -eq $Target } }

    foreach ($name in $wanted) {
        if (-not $Targets.ContainsKey($name)) {
            Write-Warning "$($file.Name): unknown announce target '$name' -- skipping."
            continue
        }
        # Not $target: PowerShell variable names are case-insensitive, so that
        # would clobber the -Target parameter and empty every later post's list.
        $def = $Targets[$name]

        # Already announced there.
        if (Test-HasKey $fm $def.UrlKey) { continue }

        $title = Get-Scalar $fm 'Title'
        $lead = Get-Scalar $fm 'Lead'
        $url = Get-PostUrl $fm
        if (-not $url) {
            Write-Warning "$($file.Name): no Published date, cannot build a URL -- skipping."
            continue
        }

        $text = (@($title, $lead, $url) | Where-Object { $_ }) -join "`n`n"
        if ($text.Length -gt 480) { $text = $text.Substring(0, 477) + '...' }

        $pending++
        Write-Host ''
        Write-Host "$($file.Name) -> $name" -ForegroundColor Cyan
        Write-Host $text

        if (-not $Publish) { continue }

        if (-not (Get-Item "env:$($def.TokenVar)" -ErrorAction SilentlyContinue)) {
            throw "$($def.TokenVar) is not set; cannot post to $name."
        }

        # Never announce a URL that is not live yet.
        if (-not $SkipUrlCheck) {
            try {
                Invoke-WebRequest -Uri $url -Method Head -MaximumRedirection 0 -TimeoutSec 20 | Out-Null
            }
            catch {
                throw "$url is not reachable yet. Deploy the post first, or pass -SkipUrlCheck."
            }
        }

        $postedUrl = & $def.Post $text

        # Write back immediately. If this fails the URL is only in this console,
        # so surface it loudly rather than letting the next run post a duplicate.
        try {
            Add-FrontMatterKey $fm $def.UrlKey $postedUrl
        }
        catch {
            Write-Host ''
            Write-Host "POSTED but FAILED TO RECORD. Add this by hand before re-running:" -ForegroundColor Red
            Write-Host "  $($def.UrlKey): $postedUrl" -ForegroundColor Red
            throw
        }

        Write-Host "  posted: $postedUrl" -ForegroundColor Green
        $done++

        # Re-read: the file changed underneath us.
        $fm = Read-FrontMatter $file.FullName
    }
}

Write-Host ''
if ($pending -eq 0) {
    Write-Host 'Nothing to announce.' -ForegroundColor Green
}
elseif ($Publish) {
    Write-Host "Announced $done of $pending." -ForegroundColor Green
    Write-Host 'Rebuild and deploy to wire up the comment widgets.'
}
else {
    Write-Host "$pending announcement(s) pending. Re-run with -Publish to post." -ForegroundColor Yellow
}
