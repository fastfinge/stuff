<#
.SYNOPSIS
    Publishes this site to AT Protocol as a standard.site publication.

.DESCRIPTION
    Makes the records on the PDS match what the last build says they should be.
    The build writes obj/standard-site.json -- the publication record and one
    document record per post, keyed by a record key derived from the post's date
    and path (see StandardSite.cs). This script compares that with what is on the
    PDS and:

        creates   documents for posts that have no record yet
        updates   documents whose title, description, tags or text have changed,
                  so a proofreading fix or a mended link goes out by itself, or
                  that have been announced on Bluesky since (bskyPostRef)
        deletes   documents for posts that no longer exist at that path
        puts      the publication record, if it is missing or has changed

    The PDS is the only state. There is nothing to commit afterwards, and a run
    that is interrupted or repeated just picks up where the PDS left off.
    Documents in the same repo that belong to some other publication -- written
    by Leaflet, say -- are never touched.

    Dry run by default: it reads the PDS (which needs no credentials) and prints
    what it would change. Pass -Publish to write.

    Run it after the deploy: a new document points at a page, and anything that
    reads the record will fetch that page to check its rel="site.standard.document"
    link. A new post whose URL is not live yet is left for the next run.

.PARAMETER Publish
    Actually write to the PDS. Needs ATPROTO_APP_PASSWORD: an app password for
    the AtprotoHandle account in settings.yml, never the account password.

.PARAMETER MaxDelete
    Refuse to run at all if it would delete more documents than this. A bad build
    that loses most of its posts should not take their records down with them.

.PARAMETER SkipUrlCheck
    Do not check that a new post is live before creating its record.

.EXAMPLE
    ./standardsite.ps1               # show what would change
    ./standardsite.ps1 -Publish      # change it
#>
[CmdletBinding()]
param(
    [switch]$Publish,
    [int]$MaxDelete = 5,
    [switch]$SkipUrlCheck,
    [string]$ManifestPath = 'obj/standard-site.json'
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
# Set-Location does not move the .NET process working directory, so a relative
# path passed to [System.IO.File] would resolve against wherever the shell was
# started. Keep the two in step.
[Environment]::CurrentDirectory = $PSScriptRoot

# JSON goes through System.Text.Json rather than ConvertFrom-Json, which turns
# every ISO date string into a DateTime. publishedAt would then never compare
# equal to what the PDS sent back, and every post would "change" on every run.
Add-Type -AssemblyName System.Text.Json
$JsonNode = [System.Text.Json.Nodes.JsonNode]

function ConvertFrom-JsonText {
    param([string]$Text)
    # The comma: a JsonObject is enumerable, and PowerShell would otherwise unroll
    # it into its key/value pairs on the way out of the function.
    return , $JsonNode::Parse($Text)
}

# Invoke-WebRequest only decodes media types it recognises as text. The DID
# document comes back as application/did+ld+json, which it hands over as bytes.
function Get-ContentText {
    param($Response)
    if ($Response.Content -is [byte[]]) { return [System.Text.Encoding]::UTF8.GetString($Response.Content) }
    return [string]$Response.Content
}

# --- Settings ------------------------------------------------------------

$settings = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'settings.yml'))
$handle = if ($settings -match '(?m)^AtprotoHandle:\s*(.+)$') { $Matches[1].Trim() } else { $null }
if ($settings -notmatch '(?m)^StandardSitePublication:\s*\S') {
    Write-Host 'StandardSitePublication is not set in settings.yml; standard.site is switched off.' -ForegroundColor DarkGray
    return
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "$ManifestPath does not exist. Build the site first: dotnet run"
}
$manifest = ConvertFrom-JsonText ([System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $ManifestPath)))
$publication = $manifest['publication']
$publicationUri = [string]$publication['uri']
$did = [string]$publication['did']
$documents = @($manifest['documents'].AsArray())

$siteUrl = [string]$publication['record']['url']

# --- PDS -----------------------------------------------------------------

# The PDS is whichever server the DID document names, not wherever the handle
# happens to point today; that is what a reader resolving the record will use.
function Resolve-Pds {
    param([string]$Did)
    $docUrl = if ($Did -like 'did:plc:*') {
        "https://plc.directory/$Did"
    }
    elseif ($Did -like 'did:web:*') {
        "https://$($Did.Substring('did:web:'.Length))/.well-known/did.json"
    }
    else { throw "Unsupported DID method: $Did" }

    $doc = ConvertFrom-JsonText (Get-ContentText (Invoke-WebRequest -Uri $docUrl -TimeoutSec 30))
    foreach ($service in $doc['service'].AsArray()) {
        if ([string]$service['id'] -like '*#atproto_pds') {
            return ([string]$service['serviceEndpoint']).TrimEnd('/')
        }
    }
    throw "$Did names no atproto_pds service."
}

$pds = Resolve-Pds $did
$session = $null

function Invoke-Xrpc {
    param(
        [string]$Method,
        [string]$Nsid,
        [hashtable]$Query,
        $Body,
        [switch]$Anonymous
    )
    $uri = "$pds/xrpc/$Nsid"
    if ($Query) {
        $pairs = $Query.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString([string]$_.Value))" }
        $uri += '?' + ($pairs -join '&')
    }
    $params = @{ Uri = $uri; Method = $Method; TimeoutSec = 60; SkipHttpErrorCheck = $true }
    if (-not $Anonymous -and $script:session) {
        $params.Headers = @{ Authorization = "Bearer $($script:session.accessJwt)" }
    }
    if ($null -ne $Body) {
        $json = if ($Body -is [System.Text.Json.Nodes.JsonNode]) { $Body.ToJsonString() } else { $Body | ConvertTo-Json -Depth 20 -Compress }
        $params.ContentType = 'application/json; charset=utf-8'
        $params.Body = [System.Text.Encoding]::UTF8.GetBytes($json)
    }
    $response = Invoke-WebRequest @params
    $content = Get-ContentText $response
    return [pscustomobject]@{
        Status = [int]$response.StatusCode
        Json   = if ($content) { ConvertFrom-JsonText $content } else { $null }
        Text   = $content
    }
}

function Assert-Ok {
    param($Response, [string]$What)
    if ($Response.Status -ge 200 -and $Response.Status -lt 300) { return }
    throw "$What failed: HTTP $($Response.Status) $($Response.Text)"
}

function Connect-Pds {
    if ($script:session) { return }
    if (-not $handle) { throw 'AtprotoHandle is not set in settings.yml.' }
    if (-not $env:ATPROTO_APP_PASSWORD) { throw 'ATPROTO_APP_PASSWORD is not set; cannot write to the PDS.' }
    $r = Invoke-Xrpc -Method Post -Nsid 'com.atproto.server.createSession' -Anonymous -Body @{
        identifier = $handle
        password   = $env:ATPROTO_APP_PASSWORD
    }
    Assert-Ok $r 'Signing in'
    # An app password for a different account would otherwise write every record
    # into the wrong repo, where nothing on this site points.
    if ([string]$r.Json['did'] -ne $did) {
        throw "Signed in as $($r.Json['did']), but the publication belongs to $did."
    }
    $script:session = [pscustomobject]@{ accessJwt = [string]$r.Json['accessJwt'] }
}

function Write-Record {
    param([string]$Collection, [string]$Rkey, [System.Text.Json.Nodes.JsonNode]$Record)
    $body = [System.Text.Json.Nodes.JsonObject]::new()
    $body['repo'] = $did
    $body['collection'] = $Collection
    $body['rkey'] = $Rkey
    $body['record'] = $Record.DeepClone()
    $r = Invoke-Xrpc -Method Post -Nsid 'com.atproto.repo.putRecord' -Body $body
    Assert-Ok $r "Writing $Collection/$Rkey"
}

function Remove-Record {
    param([string]$Collection, [string]$Rkey)
    $r = Invoke-Xrpc -Method Post -Nsid 'com.atproto.repo.deleteRecord' -Body @{
        repo = $did; collection = $Collection; rkey = $Rkey
    }
    Assert-Ok $r "Deleting $Collection/$Rkey"
}

# Is what is on the PDS the same as what the build wants there? updatedAt is
# left out of the comparison: it is set by this script when it writes a change,
# so it is never in the manifest and would otherwise always differ.
function Test-SameRecord {
    param([System.Text.Json.Nodes.JsonNode]$Wanted, [System.Text.Json.Nodes.JsonNode]$Existing)
    $existingCopy = $Existing.DeepClone()
    [void]$existingCopy.AsObject().Remove('updatedAt')
    return $JsonNode::DeepEquals($Wanted, $existingCopy)
}

# Which fields differ, for the dry run to say why it would update.
function Get-ChangedFields {
    param([System.Text.Json.Nodes.JsonNode]$Wanted, [System.Text.Json.Nodes.JsonNode]$Existing)
    $names = @($Wanted.AsObject() | ForEach-Object Key) + @($Existing.AsObject() | ForEach-Object Key) |
        Where-Object { $_ -ne 'updatedAt' } | Sort-Object -Unique
    return @($names | Where-Object { -not $JsonNode::DeepEquals($Wanted[$_], $Existing[$_]) })
}

# --- Read what is there ---------------------------------------------------

if (-not $Publish) {
    Write-Host 'DRY RUN -- nothing will be written. Pass -Publish to write for real.' -ForegroundColor Yellow
}
Write-Host "PDS: $pds" -ForegroundColor DarkGray

$existingDocs = @{}
$cursor = $null
do {
    $query = @{ repo = $did; collection = 'site.standard.document'; limit = 100 }
    if ($cursor) { $query.cursor = $cursor }
    $r = Invoke-Xrpc -Method Get -Nsid 'com.atproto.repo.listRecords' -Query $query -Anonymous
    Assert-Ok $r 'Listing documents'
    foreach ($rec in $r.Json['records'].AsArray()) {
        $existingDocs[([string]$rec['uri']).Split('/')[-1]] = $rec['value']
    }
    $cursor = if ($r.Json['cursor']) { [string]$r.Json['cursor'] } else { $null }
} while ($cursor)

# --- Work out the changes -------------------------------------------------

$changes = [System.Collections.Generic.List[object]]::new()

$pubRkey = [string]$publication['rkey']
$pubWanted = $publication['record']
$r = Invoke-Xrpc -Method Get -Nsid 'com.atproto.repo.getRecord' -Anonymous -Query @{
    repo = $did; collection = 'site.standard.publication'; rkey = $pubRkey
}
if ($r.Status -eq 200) {
    if (-not (Test-SameRecord $pubWanted $r.Json['value'])) {
        $changes.Add([pscustomobject]@{ Action = 'update'; Collection = 'site.standard.publication'; Rkey = $pubRkey
            Record = $pubWanted; Label = 'publication'; Detail = (Get-ChangedFields $pubWanted $r.Json['value']) -join ', ' })
    }
}
elseif ($r.Status -eq 400 -and [string]$r.Json['error'] -eq 'RecordNotFound') {
    $changes.Add([pscustomobject]@{ Action = 'create'; Collection = 'site.standard.publication'; Rkey = $pubRkey
        Record = $pubWanted; Label = 'publication'; Detail = [string]$pubWanted['name'] })
}
else {
    Assert-Ok $r 'Reading the publication record'
}

# bskyPostRef: a post announced on Bluesky links its document to that post, which
# is where its Bluesky replies hang. The build knows the post's URI but a strong
# ref needs its CID too, so read the post record for it. A post that cannot be
# read is left without the ref this time, rather than with a wrong one.
foreach ($doc in $documents) {
    $bskyPost = [string]$doc['bskyPost']
    if (-not $bskyPost) { continue }
    $parts = $bskyPost.Substring('at://'.Length).Split('/')
    $r = Invoke-Xrpc -Method Get -Nsid 'com.atproto.repo.getRecord' -Anonymous -Query @{
        repo = $parts[0]; collection = $parts[1]; rkey = $parts[2]
    }
    if ($r.Status -ne 200 -or -not $r.Json['cid']) {
        Write-Warning "$($doc['record']['path']) : could not read $bskyPost (HTTP $($r.Status)); no bskyPostRef this run."
        continue
    }
    $ref = [System.Text.Json.Nodes.JsonObject]::new()
    $ref['uri'] = [string]$r.Json['uri']
    $ref['cid'] = [string]$r.Json['cid']
    $doc['record']['bskyPostRef'] = $ref
}

$wantedKeys = @{}
foreach ($doc in $documents) {
    $rkey = [string]$doc['rkey']
    $wanted = $doc['record']
    $path = [string]$wanted['path']
    $wantedKeys[$rkey] = $true

    if (-not $existingDocs.ContainsKey($rkey)) {
        $changes.Add([pscustomobject]@{ Action = 'create'; Collection = 'site.standard.document'; Rkey = $rkey
            Record = $wanted; Label = $path; Detail = [string]$wanted['title'] })
        continue
    }

    $existing = $existingDocs[$rkey]
    if ([string]$existing['site'] -ne $publicationUri) {
        # Keys are derived from a hash, so this should never happen. If it does,
        # overwriting would destroy someone else's document.
        Write-Warning "$path : key $rkey is already used by a document of $($existing['site']); leaving both alone."
        continue
    }
    if (-not (Test-SameRecord $wanted $existing)) {
        $changes.Add([pscustomobject]@{ Action = 'update'; Collection = 'site.standard.document'; Rkey = $rkey
            Record = $wanted; Label = $path; Detail = (Get-ChangedFields $wanted $existing) -join ', ' })
    }
}

foreach ($rkey in $existingDocs.Keys) {
    $existing = $existingDocs[$rkey]
    if ([string]$existing['site'] -ne $publicationUri -or $wantedKeys.ContainsKey($rkey)) { continue }
    $changes.Add([pscustomobject]@{ Action = 'delete'; Collection = 'site.standard.document'; Rkey = $rkey
        Record = $null; Label = [string]$existing['path']; Detail = [string]$existing['title'] })
}

$deletes = @($changes | Where-Object Action -eq 'delete').Count
if ($deletes -gt $MaxDelete) {
    $changes | Where-Object Action -eq 'delete' | ForEach-Object { Write-Host "  delete $($_.Label)  ($($_.Detail))" }
    throw "Refusing to delete $deletes documents (more than -MaxDelete $MaxDelete). If that is really intended, re-run with a higher -MaxDelete."
}

# --- Report, and apply ----------------------------------------------------

if ($changes.Count -eq 0) {
    Write-Host "Up to date: the publication and all $($documents.Count) documents match the PDS." -ForegroundColor Green
    return
}

$colours = @{ create = 'Green'; update = 'Cyan'; delete = 'Red' }
$done = 0
$skipped = 0

foreach ($change in $changes) {
    Write-Host ("{0,-6} {1}  ({2})" -f $change.Action, $change.Label, $change.Detail) -ForegroundColor $colours[$change.Action]
    if (-not $Publish) { continue }

    # A new document should not point at a page that is not there yet. Not an
    # error: the next run after the deploy will pick it up.
    if ($change.Action -eq 'create' -and $change.Collection -eq 'site.standard.document' -and -not $SkipUrlCheck) {
        $url = $siteUrl + $change.Label
        try {
            Invoke-WebRequest -Uri $url -Method Head -MaximumRedirection 0 -TimeoutSec 20 | Out-Null
        }
        catch {
            Write-Warning "$url is not live yet; skipped. Deploy first, or pass -SkipUrlCheck."
            $skipped++
            continue
        }
    }

    Connect-Pds
    switch ($change.Action) {
        'delete' { Remove-Record $change.Collection $change.Rkey }
        'create' { Write-Record $change.Collection $change.Rkey $change.Record }
        'update' {
            $record = $change.Record.DeepClone()
            $record['updatedAt'] = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [cultureinfo]::InvariantCulture)
            Write-Record $change.Collection $change.Rkey $record
        }
    }
    $done++
}

Write-Host ''
if (-not $Publish) {
    Write-Host "$($changes.Count) change(s) pending. Re-run with -Publish to write them." -ForegroundColor Yellow
    return
}
Write-Host "Wrote $done of $($changes.Count) change(s)$(if ($skipped) { "; $skipped skipped until their pages are live" })." -ForegroundColor Green

# The publication only counts once the domain vouches for it. Check the live file
# rather than trust that the deploy carried it, and say so if it did not.
try {
    $live = Get-ContentText (Invoke-WebRequest -Uri "$siteUrl/.well-known/site.standard.publication" -TimeoutSec 20)
    if ($live.Trim() -ne $publicationUri) {
        Write-Warning "$siteUrl/.well-known/site.standard.publication says '$($live.Trim())', not $publicationUri. Deploy the current build."
    }
}
catch {
    Write-Warning "$siteUrl/.well-known/site.standard.publication is not reachable. Deploy the current build."
}
