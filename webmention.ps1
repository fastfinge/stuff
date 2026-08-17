<#
.SYNOPSIS
    Sends webmentions for every outbound link in the published posts.

.DESCRIPTION
    Receiving webmentions is delegated to webmention.io (see settings.yml).
    Sending them is this script's job, and nothing else does it: a static site
    has no moment of "publish" at which it could notice a new link.

    It reads output/, so run it after a build and after the post is live -- a
    receiver fetches the source URL to verify the link really exists, and will
    reject a page it cannot fetch.

    Only links inside a post's <article class="h-entry"> are considered, which is
    what keeps it from mentioning the navigation, the footer, and the linkblog
    on every post in the archive. Links back to this site are skipped too.

    Dry run by default: it prints what it would send and changes nothing. Pass
    -Send to actually send.

    Every (source, target) pair that gets a response is recorded in
    webmentions-sent.json and never sent again. On a site that has never sent
    any, the first run is therefore the whole back catalogue; look at the dry
    run before committing to it, and use -Since or -MarkSent to draw a line.

.PARAMETER Send
    Actually send. Without this, nothing is sent and the state file is untouched.

.PARAMETER Since
    Only consider posts published on or after this date, taken from the post URL.

.PARAMETER Post
    Only consider posts whose URL contains this text, e.g. a slug.

.PARAMETER MarkSent
    Record every pending mention as sent without sending it. Use once, to avoid
    mentioning years of old links, then forget it exists.

.PARAMETER Resend
    Ignore the state file and consider every link again. Receivers are required
    to cope with a repeat, so this is safe, just noisy.

.PARAMETER Check
    During a dry run, look each target up and report whether it accepts
    webmentions at all. Read-only, but it does fetch every target, so it is slow.
    Most of the web does not accept them; this is how to see which few do.

.EXAMPLE
    ./webmention.ps1                      # show what would be sent
    ./webmention.ps1 -Check               # ...and which of them would be accepted
    ./webmention.ps1 -Since 2026-01-01    # ...only for this year's posts
    ./webmention.ps1 -Send                # send it
    ./webmention.ps1 -MarkSent            # draw a line under everything older
#>
[CmdletBinding()]
param(
    [switch]$Send,
    [datetime]$Since,
    [string]$Post,
    [switch]$MarkSent,
    [switch]$Resend,
    [switch]$Check,
    [string]$OutputPath = 'output',
    [string]$StatePath = 'webmentions-sent.json'
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
# Set-Location does not move the .NET process working directory, so a relative
# path passed to [System.IO.File] would resolve against wherever the shell was
# started. Keep the two in step.
[Environment]::CurrentDirectory = $PSScriptRoot

$UserAgent = 'stuff.interfree.ca webmention sender (+https://stuff.interfree.ca/)'

# --- Site config ---------------------------------------------------------
# Same two lines announce.ps1 reads, for the same reason: the URL a post is
# published at is a fact about settings.yml, not something to hardcode twice.

$settings = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'settings.yml'))
$host_ = if ($settings -match '(?m)^Host:\s*(.+)$') { $Matches[1].Trim() } else { throw 'No Host in settings.yml' }
$scheme = if ($settings -match '(?m)^LinksUseHttps:\s*true') { 'https' } else { 'http' }
$siteRoot = "${scheme}://${host_}"

# --- State ---------------------------------------------------------------

function Read-State {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @{} }
    $json = [System.IO.File]::ReadAllText($Path)
    if (-not $json.Trim()) { return @{} }
    return [System.Collections.Hashtable](ConvertFrom-Json $json -AsHashtable)
}

function Write-State {
    param([hashtable]$State, [string]$Path)
    $encoding = New-Object System.Text.UTF8Encoding($false)
    $json = $State | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($Path, $json, $encoding)
}

# --- Discovery -----------------------------------------------------------

# Posts live at /yyyy/MM/dd/slug.html and nothing else does, so the path is a
# good enough test for "is this a post" without re-reading the front matter.
function Get-PostPages {
    param([string]$Root)

    $full = (Resolve-Path -LiteralPath $Root).Path
    Get-ChildItem -LiteralPath $full -Filter '*.html' -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($full.Length).TrimStart('\', '/').Replace('\', '/')
        if ($relative -match '^(\d{4})/(\d{2})/(\d{2})/[^/]+\.html$') {
            [pscustomobject]@{
                Path      = $_.FullName
                Url       = "$siteRoot/$relative"
                Published = [datetime]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3])
            }
        }
    }
}

# Only the entry itself. Everything outside it -- nav, footer, linkblog, the
# comments fetched from elsewhere -- is on every page, and mentioning those from
# each of forty posts would be indistinguishable from spam.
function Get-EntryLinks {
    param([string]$Html)

    $entry = [regex]::Match($Html, '(?is)<article\b[^>]*\bclass\s*=\s*["''][^"'']*\bh-entry\b[^"'']*["''][^>]*>(.*?)</article>')
    if (-not $entry.Success) { return @() }

    $urls = [System.Collections.Generic.List[string]]::new()
    foreach ($m in [regex]::Matches($entry.Groups[1].Value, '(?is)<a\b[^>]*>')) {
        $tag = $m.Value
        if ($tag -notmatch '(?is)\bhref\s*=\s*["'']([^"'']+)["'']') { continue }
        $href = [System.Net.WebUtility]::HtmlDecode($Matches[1].Trim())

        # u-syndication points at this post's own copy on another network, not at
        # someone else's page. Mentioning it would be telling the fediverse about
        # a post the fediverse already has.
        if ($tag -match '(?is)\brel\s*=\s*["'']?([^"''>]*)["'']?' -and
            ($Matches[1].Trim() -split '\s+') -contains 'syndication') { continue }

        $uri = $null
        if (-not [uri]::TryCreate($href, [System.UriKind]::Absolute, [ref]$uri)) { continue }
        if ($uri.Scheme -notin @('http', 'https')) { continue }
        # A link home is not a mention; webmention.io would reject it anyway.
        if ($uri.Host -eq $host_) { continue }

        $clean = $uri.GetLeftPart([System.UriPartial]::Query)
        if (-not $urls.Contains($clean)) { $urls.Add($clean) }
    }
    return $urls
}

function Resolve-Endpoint {
    param([string]$Href, [uri]$Base)
    # An empty href means "this page is its own endpoint", which is legal.
    if ([string]::IsNullOrWhiteSpace($Href)) { return $Base.AbsoluteUri }
    $resolved = $null
    if ([uri]::TryCreate($Base, $Href, [ref]$resolved)) { return $resolved.AbsoluteUri }
    return $null
}

# Per the spec: the first Link header wins, then the first link or a element in
# the document. rel is a space separated token list, so "me webmention" counts
# and "webmention-endpoint" does not.
function Get-WebmentionEndpoint {
    param([string]$Target)

    try {
        $response = Invoke-WebRequest -Uri $Target -Method Get -MaximumRedirection 5 `
            -TimeoutSec 30 -UserAgent $UserAgent -SkipHttpErrorCheck -ErrorAction Stop
    }
    catch {
        return [pscustomobject]@{ Endpoint = $null; Error = $_.Exception.Message }
    }

    if ($response.StatusCode -ge 400) {
        return [pscustomobject]@{ Endpoint = $null; Error = "HTTP $($response.StatusCode)" }
    }

    # Resolve relative endpoints against where we actually ended up, not against
    # where we started, or a redirect would send the mention to the wrong host.
    $base = [uri]$Target
    if ($response.BaseResponse.RequestMessage.RequestUri) {
        $base = $response.BaseResponse.RequestMessage.RequestUri
    }

    $linkHeaders = if ($response.Headers.ContainsKey('Link')) { @($response.Headers['Link']) } else { @() }
    foreach ($header in $linkHeaders) {
        if (-not $header) { continue }
        foreach ($m in [regex]::Matches([string]$header, '<([^>]*)>\s*;\s*([^,]*)')) {
            $params = $m.Groups[2].Value
            if ($params -match '(?i)rel\s*=\s*"?([^";,]+)"?') {
                if (($Matches[1].Trim() -split '\s+') -contains 'webmention') {
                    return [pscustomobject]@{ Endpoint = (Resolve-Endpoint $m.Groups[1].Value.Trim() $base); Error = $null }
                }
            }
        }
    }

    foreach ($m in [regex]::Matches([string]$response.Content, '(?is)<(?:link|a)\b[^>]*>')) {
        $tag = $m.Value
        if ($tag -notmatch '(?is)\brel\s*=\s*["'']?([^"''>]*)["'']?') { continue }
        if (($Matches[1].Trim() -split '\s+') -notcontains 'webmention') { continue }
        if ($tag -notmatch '(?is)\bhref\s*=\s*["'']([^"'']*)["'']') { continue }
        $href = [System.Net.WebUtility]::HtmlDecode($Matches[1])
        return [pscustomobject]@{ Endpoint = (Resolve-Endpoint $href $base); Error = $null }
    }

    return [pscustomobject]@{ Endpoint = $null; Error = 'no endpoint advertised' }
}

function Send-Webmention {
    param([string]$Endpoint, [string]$Source, [string]$Target)

    $response = Invoke-WebRequest -Uri $Endpoint -Method Post `
        -Body @{ source = $Source; target = $Target } `
        -TimeoutSec 60 -UserAgent $UserAgent -SkipHttpErrorCheck -ErrorAction Stop
    return [int]$response.StatusCode
}

# --- Main ----------------------------------------------------------------

if (-not (Test-Path -LiteralPath $OutputPath)) {
    throw "No $OutputPath directory. Build the site first: dotnet run"
}

if (-not $Send -and -not $MarkSent) {
    Write-Host 'DRY RUN -- nothing will be sent. Pass -Send to send for real.' -ForegroundColor Yellow
}

$state = if ($Resend) { @{} } else { Read-State $StatePath }
$posts = Get-PostPages $OutputPath | Sort-Object Published

if ($Since) { $posts = $posts | Where-Object { $_.Published -ge $Since } }
if ($Post) { $posts = $posts | Where-Object { $_.Url -like "*$Post*" } }

$pending = 0
$sent = 0
$failed = 0
$now = (Get-Date).ToUniversalTime().ToString('o')
# One page can be linked from several posts; discovery is per target, not per pair.
$endpoints = @{}

foreach ($page in $posts) {
    $html = [System.IO.File]::ReadAllText($page.Path)
    $targets = Get-EntryLinks $html
    if (-not $targets) { continue }

    $alreadySent = if ($state.ContainsKey($page.Url)) { $state[$page.Url] } else { @{} }
    $new = @($targets | Where-Object { -not $alreadySent.ContainsKey($_) })
    if (-not $new) { continue }

    Write-Host ''
    Write-Host $page.Url -ForegroundColor Cyan

    foreach ($target in $new) {
        $pending++

        if (-not $Send -and -not $MarkSent) {
            if (-not $Check) {
                Write-Host "  -> $target"
                continue
            }
            if (-not $endpoints.ContainsKey($target)) {
                $endpoints[$target] = Get-WebmentionEndpoint $target
            }
            $discovery = $endpoints[$target]
            if ($discovery.Endpoint) {
                Write-Host "  -> $target" -ForegroundColor Green
                Write-Host "     accepts webmentions at $($discovery.Endpoint)" -ForegroundColor Green
                $sent++
            }
            else {
                Write-Host "  -> $target ($($discovery.Error))" -ForegroundColor DarkGray
            }
            continue
        }

        if ($MarkSent) {
            $alreadySent[$target] = @{ at = $now; status = 0; endpoint = $null; note = 'marked sent without sending' }
            $state[$page.Url] = $alreadySent
            Write-Host "  marked $target" -ForegroundColor DarkGray
            $sent++
            continue
        }

        if (-not $endpoints.ContainsKey($target)) {
            $endpoints[$target] = Get-WebmentionEndpoint $target
        }
        $discovery = $endpoints[$target]

        if (-not $discovery.Endpoint) {
            # Most sites do not accept webmentions. That is not a failure worth
            # a red line, and it is not worth re-checking on every future run
            # either, so it is recorded like any other outcome.
            Write-Host "  skip $target ($($discovery.Error))" -ForegroundColor DarkGray
            $alreadySent[$target] = @{ at = $now; status = 0; endpoint = $null; note = $discovery.Error }
            $state[$page.Url] = $alreadySent
            continue
        }

        try {
            $status = Send-Webmention -Endpoint $discovery.Endpoint -Source $page.Url -Target $target
        }
        catch {
            Write-Warning "  $target -- $($_.Exception.Message)"
            $failed++
            continue
        }

        if ($status -ge 200 -and $status -lt 300) {
            Write-Host "  sent $target (HTTP $status)" -ForegroundColor Green
            $sent++
            $alreadySent[$target] = @{ at = $now; status = $status; endpoint = $discovery.Endpoint; note = $null }
            $state[$page.Url] = $alreadySent
        }
        else {
            # Not recorded, so the next run tries again: a 5xx is the receiver
            # having a bad day, not an answer.
            Write-Warning "  $target -- endpoint returned HTTP $status"
            $failed++
        }
    }
}

if ($Send -or $MarkSent) {
    Write-State $state $StatePath
}

Write-Host ''
if ($pending -eq 0) {
    Write-Host 'No new links to mention.' -ForegroundColor Green
}
elseif ($MarkSent) {
    Write-Host "Marked $sent link(s) as sent without sending them." -ForegroundColor Green
}
elseif ($Send) {
    Write-Host "Sent $sent of $pending. $failed failed." -ForegroundColor Green
    if ($failed -gt 0) {
        Write-Host 'Failures are not recorded, so re-running retries them.' -ForegroundColor Yellow
    }
}
elseif ($Check) {
    Write-Host "$sent of $pending link(s) accept webmentions. Re-run with -Send to send them." -ForegroundColor Yellow
}
else {
    Write-Host "$pending link(s) pending. Re-run with -Send to send them." -ForegroundColor Yellow
}
