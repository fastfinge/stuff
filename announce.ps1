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
    (fedi -> Fedi:, bluesky -> Bluesky:), which is both what the comment widget
    reads and how this script knows the post has already been announced there.
    A target that already has its key is skipped, so re-running is safe. A target
    whose credentials are not set is skipped with a warning, and picked up by the
    next run that has them.

    fedi needs FEDI_TOKEN. bluesky posts from the AtprotoHandle account in
    settings.yml and needs ATPROTO_APP_PASSWORD, the same app password
    standardsite.ps1 uses.

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
# Set-Location does not move the .NET process working directory, so a relative
# path passed to [System.IO.File] would resolve against wherever the shell was
# started. Keep the two in step.
[Environment]::CurrentDirectory = $PSScriptRoot

# --- Targets -------------------------------------------------------------
# To add a network later, add an entry here and implement its Post block.
# UrlKey is the front matter key holding the resulting URL. Limit is the
# network's post length in graphemes; the text is cut to fit, never the URL.
# Post gets the text and the post's Title, Lead and Url, and returns the URL of
# what it posted.
$Targets = @{
    fedi = @{
        UrlKey   = 'Fedi'
        TokenVar = 'FEDI_TOKEN'
        Limit    = 480
        Post     = {
            param($text, $post)
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
    bluesky = @{
        UrlKey   = 'Bluesky'
        TokenVar = 'ATPROTO_APP_PASSWORD'
        Limit    = 300
        Post     = {
            param($text, $post)
            return Publish-BlueskyPost $text $post
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

$settings = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'settings.yml'))
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

# --- Text ----------------------------------------------------------------

# Title, lead and URL, one paragraph each, cut to Limit graphemes. The lead is
# shortened first and then the title; the URL never is, because a truncated link
# is a broken one in a post that cannot be edited afterwards. Graphemes rather
# than chars, because that is what Bluesky counts, and an emoji or accented
# letter is more than one char.
function Format-Announcement {
    param([string]$Title, [string]$Lead, [string]$Url, [int]$Limit)

    function Measure-Text([string]$s) { ([System.Globalization.StringInfo]::new($s)).LengthInTextElements }
    function Limit-Text([string]$s, [int]$max) {
        $info = [System.Globalization.StringInfo]::new($s)
        if ($info.LengthInTextElements -le $max) { return $s }
        if ($max -lt 2) { return '' }
        return $info.SubstringByTextElements(0, $max - 1).TrimEnd() + [char]0x2026
    }
    function Join-Parts([string[]]$parts) { (@($parts) | Where-Object { $_ }) -join "`n`n" }

    $text = Join-Parts @($Title, $Lead, $Url)
    $over = (Measure-Text $text) - $Limit
    if ($over -le 0) { return $text }

    if ($Lead) {
        $Lead = Limit-Text $Lead ((Measure-Text $Lead) - $over)
        $text = Join-Parts @($Title, $Lead, $Url)
        $over = (Measure-Text $text) - $Limit
        if ($over -le 0) { return $text }
    }
    $Title = Limit-Text $Title ((Measure-Text $Title) - $over)
    return Join-Parts @($Title, $Lead, $Url)
}

# --- Bluesky -------------------------------------------------------------

$atprotoHandle = if ($settings -match '(?m)^AtprotoHandle:\s*(.+)$') { $Matches[1].Trim() } else { $null }

# Handle to DID the way the protocol defines it, not by asking an AppView: the
# handle's own https://HANDLE/.well-known/atproto-did, then its _atproto DNS TXT
# record. Resolve-DnsName only exists on Windows, so on Linux (CI) the web file
# is the only route -- which is how this site's handle is set up anyway.
function Resolve-AtprotoHandle {
    param([string]$Handle)
    try {
        $did = ([string](Invoke-RestMethod -Uri "https://$Handle/.well-known/atproto-did" -TimeoutSec 30)).Trim()
        if ($did -like 'did:*') { return $did }
    }
    catch { }
    if (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue) {
        $txt = Resolve-DnsName -Name "_atproto.$Handle" -Type TXT -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Strings } | Where-Object { $_ -like 'did=*' } | Select-Object -First 1
        if ($txt) { return $txt.Substring(4) }
    }
    throw "Could not resolve $Handle to a DID: no https://$Handle/.well-known/atproto-did and no usable _atproto TXT record."
}

# The PDS is whichever server the DID document names, as in standardsite.ps1.
# With -Handle, also check the DID document claims that handle back; a handle is
# only valid when both directions agree.
function Resolve-AtprotoPds {
    param([string]$Did, [string]$Handle)
    $docUrl = if ($Did -like 'did:plc:*') { "https://plc.directory/$Did" }
              elseif ($Did -like 'did:web:*') { "https://$($Did.Substring('did:web:'.Length))/.well-known/did.json" }
              else { throw "Unsupported DID method: $Did" }
    $doc = Invoke-RestMethod -Uri $docUrl -TimeoutSec 30
    if ($Handle -and @($doc.alsoKnownAs) -notcontains "at://$Handle") {
        throw "$Handle points at $Did, but that DID does not claim $Handle."
    }
    $service = @($doc.service) | Where-Object { $_.id -like '*#atproto_pds' } | Select-Object -First 1
    if (-not $service) { throw "$Did names no atproto_pds service." }
    return ([string]$service.serviceEndpoint).TrimEnd('/')
}

# Posts straight to the account's own PDS; Bluesky picks it up from there. The
# URL in the text gets a link facet, because Bluesky does not turn URLs in post
# text into links by itself, and an external embed so it shows as a link card.
function Publish-BlueskyPost {
    param([string]$Text, $Post)

    if (-not $atprotoHandle) { throw 'AtprotoHandle is not set in settings.yml.' }
    $did = Resolve-AtprotoHandle $atprotoHandle
    $pds = Resolve-AtprotoPds $did -Handle $atprotoHandle

    $session = Invoke-RestMethod -Method Post -Uri "$pds/xrpc/com.atproto.server.createSession" -TimeoutSec 60 `
        -ContentType 'application/json; charset=utf-8' `
        -Body ([System.Text.Encoding]::UTF8.GetBytes((@{ identifier = $atprotoHandle; password = $env:ATPROTO_APP_PASSWORD } | ConvertTo-Json -Compress)))
    if ([string]$session.did -ne $did) {
        throw "Signed in as $($session.did), but $atprotoHandle is $did."
    }

    $record = [ordered]@{
        '$type'   = 'app.bsky.feed.post'
        text      = $Text
        createdAt = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [cultureinfo]::InvariantCulture)
        embed     = @{
            '$type'  = 'app.bsky.embed.external'
            external = @{
                uri         = $Post.Url
                title       = [string]$Post.Title
                description = [string]$Post.Lead
            }
        }
    }

    # Facet offsets count UTF-8 bytes, not chars.
    $at = $Text.LastIndexOf($Post.Url, [System.StringComparison]::Ordinal)
    if ($at -ge 0) {
        $start = [System.Text.Encoding]::UTF8.GetByteCount($Text.Substring(0, $at))
        $record.facets = @(@{
            index    = @{ byteStart = $start; byteEnd = $start + [System.Text.Encoding]::UTF8.GetByteCount($Post.Url) }
            features = @(@{ '$type' = 'app.bsky.richtext.facet#link'; uri = $Post.Url })
        })
    }

    $body = @{ repo = $did; collection = 'app.bsky.feed.post'; record = $record } | ConvertTo-Json -Depth 10 -Compress
    $response = Invoke-RestMethod -Method Post -Uri "$pds/xrpc/com.atproto.repo.createRecord" -TimeoutSec 60 `
        -Headers @{ Authorization = "Bearer $($session.accessJwt)" } `
        -ContentType 'application/json; charset=utf-8' `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($body))
    if (-not $response.uri) { throw 'The PDS response contained no uri field.' }

    # The handle form rather than the DID: it is the URL anyone who finds the
    # post on Bluesky sees, which is what original-post-discovery matches against.
    $rkey = ([string]$response.uri).Split('/')[-1]
    return "https://bsky.app/profile/$atprotoHandle/post/$rkey"
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

        $text = Format-Announcement -Title $title -Lead $lead -Url $url -Limit $def.Limit

        $pending++
        Write-Host ''
        Write-Host "$($file.Name) -> $name" -ForegroundColor Cyan
        Write-Host $text

        if (-not $Publish) { continue }

        # Not fatal: one network's missing credentials should not hold back the
        # others. The post keeps no key for this target, so the next run that
        # has them announces it.
        if (-not (Get-Item "env:$($def.TokenVar)" -ErrorAction SilentlyContinue)) {
            Write-Warning "$($def.TokenVar) is not set; not posting to $name this time."
            continue
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

        $postedUrl = & $def.Post $text ([pscustomobject]@{ Title = $title; Lead = $lead; Url = $url })

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
