# Sam's Stuff

Source for [stuff.interfree.ca](https://stuff.interfree.ca), a [Statiq Web](https://statiq.dev) site
using the [CleanBlog](https://github.com/statiqdev/CleanBlog) theme.

## Writing a post

Add a Markdown file under `input/posts/YYYY/MM/DD/slug.md`:

```
Title: Your Title
Published: 2026-05-24
Lead: One-sentence summary shown under the title and in feeds.
Tags:
- articles
Fedi: https://fed.interfree.ca/notes/xxxxxxxx
---
Body goes here.
```

The output path comes from the `Published` date in the front matter (see
`input/posts/_directory.yml`), not from the folder the file sits in — though
keeping them in step makes things easier to find.

Commit and push to `main`. GitHub Actions builds and deploys.

## Building locally

```
dotnet run              # build into output/
dotnet run -- preview   # build and serve at http://localhost:5080
```

`output/`, `cache/`, `temp/`, and `theme/` are all generated and git-ignored.

## Third-party scripts

There are none at runtime. Everything the pages load is served from this domain:
the fonts in `input/js/fonts/`, and Prism, quicklink, lunr and pako in
`input/js/vendor/`, all pinned to the versions the theme asked for.

That includes syntax highlighting. Prism's autoloader fetches one grammar per
language actually used on a page, and the theme leaves it pointing at jsdelivr,
so a code block would have meant a request to a CDN from the reader's browser
*at read time* — which mirroring at build time cannot intercept. All 298 Prism
1.29.0 language grammars are therefore vendored in
`input/js/vendor/prism-components/` (560 KB on disk, and a reader downloads only
the one or two their page needs), and the autoloader is pointed at them with
`data-autoloader-path` in `input/_layout.cshtml`. Nothing to configure when you
use a new language: write the fence and it works.

````
```powershell
Write-Host "highlighted"
```
````

A fence with no language is left unhighlighted on purpose, and the build's
`FencedCodeBlocksShouldHaveLanguage` analyzer will point it out.

The theme points those four at jsdelivr and relies on Statiq's `MirrorResources`
to pull them local during the build. That setting is off, because the module
does its rewriting by round-tripping every page through an HTML parser, and the
round-trip **double-encodes entities in attribute values**: a `&` in a link URL
came out as `&amp;` (so `?id=x&hl=en_US` requested a parameter called `amp;hl`),
and `Sam's Stuff` came out as `Sam&#x27;s Stuff` in the `og:` tags and feed link
titles. Vendoring the files leaves `MirrorResources` nothing to rewrite.

Upgrading is manual and rare: re-download the file, keep the name, done. Note
that `Statiq.Web` is pinned at `1.0.0-beta.60` (the newest published) while
`Devlead.Statiq` pulls `Statiq.Core` up to `beta.72`, so the two are not from the
same build — that skew is the likely cause of the encoding bug, and it is worth
re-testing the above if either package moves.

## The links page

`input/pages/links.md` renders the linkblog at
[stream.interfree.ca](https://stream.interfree.ca) via the `LinkBlog` shortcode:

```
<?# LinkBlog /?>
```

Optional arguments: `Feed` (defaults to the linkblog RSS URL) and `Count`
(defaults to 50). The shortcode is implemented in `LinkBlogShortcode.cs`; it
fetches and parses the feed during the build. If the feed can't be reached the
build logs a warning and the page says so, rather than failing the whole site.

This replaces the previous `tinyfeed.exe` + `update.ps1` approach, which needed
a checked-in 14 MB binary, escaped `@media` to `@@media` so Razor wouldn't choke
on the generated file, and mangled non-ASCII characters as it piped through
PowerShell.

## Linking a book in a review

The `Book` shortcode takes an Open Library ID and renders the cover, title and
author, linked to the book's Open Library page:

```
<?# Book OL42557111W /?>
```

Open Library is the link target on purpose: its page lists every edition, plus
borrowing and buying options, so readers choose where to get the book instead of
being sent to Amazon.

The ID can be a work (`OL...W`) or an edition (`OL...M`), and a pasted Open
Library URL works too — the ID is picked out of it. Optional arguments:

- `Title`, `Author` — override what Open Library has, or supply it when the
  record is thin
- `Cover` — a site-relative path or URL to use instead of the Open Library
  cover. Self-published books are often catalogued with no cover at all
- `Size` — `S`, `M` or `L` for the Open Library cover. Defaults to `L`

Implemented in `BookShortcode.cs`; it fetches from Open Library's search API
during the build, so the published page is plain HTML with no third-party
JavaScript, iframe, or request from the reader's browser except the cover image.

This replaces Open Library's `/widget` iframe, which is a separate unlabelled
document to a screen reader, can't be styled to match the site, and for these
books was rendering an empty `<img>` anyway because the works have no cover on
file.

If a book can't be looked up, the build logs a warning and falls back to a plain
link, rather than failing. A malformed ID logs a warning and renders nothing, so
watch the build output after adding one.

## IndieWeb

The site implements the [IndieWeb specifications](https://indieweb.org/specifications)
that a static site can implement, which is most of them. Nothing here depends on
a third-party script running in the reader's browser to work; the markup is
generated at build time, and the two moving parts (sending webmentions, pinging
the WebSub hub) are scripts that run after a deploy.

Endpoints and identities are configured in `settings.yml` under `Identity` and
`IndieWeb`, not scattered through the templates.

### microformats2 — h-entry, h-feed, h-card, h-cite

This is the part everything else is built on: it is how another site reads a post
here as a post rather than as a page of text.

- **h-entry.** A post page is one `article.h-entry`, opened in `_layout.cshtml`
  *before* the masthead, because the title, summary, date, author and tags all
  live in the masthead. It carries `p-name`, `p-summary`, `u-url`, `u-uid`,
  `dt-published`, `dt-updated`, `p-author`, `p-category` and `e-content`.
- `e-content` wraps the post body only. The syndication links below it and the
  comments below those are deliberately outside it — the comments are other
  people's posts, and a parser that read them as part of this one would quote
  them back as if they were.
- **h-feed.** The home page, `/posts/`, and each tag page are an `h-feed` of
  `h-entry` previews. `_layout.cshtml` decides this by asking whether the page's
  children are posts, so no template needs a flag. The masthead heading becomes
  the feed's `p-name`.
- **h-card.** The footer card is the site's *representative* h-card: its `u-url`
  and `u-uid` are the home page and it carries `rel=me`, which is what makes it
  the answer to "who is https://stuff.interfree.ca/". Properties are written out
  rather than left implied, because implied photo only applies to an h-card whose
  single child is an image, and this one also has a name.
- **h-cite.** The `Book` shortcode emits `h-cite` alongside its schema.org
  microdata, so a book in a review is machine-readable as a citation.

Check the markup after changing a template. [Parse this page](https://indiewebify.me/validate-h-entry/)
or, locally, `pip install mf2py` and:

```
python -c "import mf2py,json;print(json.dumps(mf2py.parse(doc=open('output/index.html',encoding='utf-8').read(),url='https://stuff.interfree.ca/'),indent=1)[:2000])"
```

### authorship

Each post carries an explicit `p-author` h-card in its byline, so a consumer
never has to fetch a second page. `rel=author` in the head points at the home
page as the fallback, and the representative h-card there answers it.

### rel-me and IndieAuth

`RelMe` in `settings.yml` lists the accounts that are mine. Each becomes a
`<link rel="me">`. These are only *claims* until the account links back here —
add the return link on the other end before adding a line here, or an IndieAuth
provider will refuse the pair.

`authorization_endpoint` and `token_endpoint` delegate sign-in to
[indieauth.com](https://indieauth.com/), which authenticates by walking those
rel=me links. That is what lets `https://stuff.interfree.ca/` be used as a login
on other IndieWeb sites.

There is no `rel=indieauth-metadata` document. A metadata document has to name
its issuer, the issuer has to be the authorization server, and this site is not
the authorization server — publishing one naming indieauth.com as issuer from
this domain would be asking clients to trust a mismatch. Modern IndieAuth clients
fall back to the two `rel` values above, so nothing is lost.

### Webmention

**Receiving** is delegated to [webmention.io](https://webmention.io) — a static
site cannot accept a POST. `rel=webmention` and `rel=pingback` point there, and
`js/webmention.min.js` reads them back to fill the "Webmentions" section under a
post.

**Sending** is `./webmention.ps1`, and nothing else does it: a static site has no
moment of "publish" at which it could notice a new outbound link.

```
./webmention.ps1                    # dry run: what would be sent
./webmention.ps1 -Check             # ...and which targets actually accept them
./webmention.ps1 -Send              # send
./webmention.ps1 -Since 2026-01-01  # only this year's posts
./webmention.ps1 -MarkSent          # record everything as sent, without sending
```

It reads `output/`, so build first, and run it *after* the post is live: a
receiver fetches the source URL to verify the link exists and rejects what it
cannot fetch. Only links inside a post's `article.h-entry` count, which is what
keeps the navigation, the footer and the linkblog from being mentioned once per
post; links marked `rel=syndication` and links back to this site are skipped too.

Every pair that gets an answer is recorded in `webmentions-sent.json` and never
sent twice. **On a site that has never sent any, the first run is the entire back
catalogue** — look at the dry run first, and use `-MarkSent` once to draw a line
under the archive if you would rather start from today.

### WebSub

`WebSubHub` in `settings.yml` names the hub. `WebSubLinks.cs` injects
`rel="hub"` and a correct `rel="self"` into the RSS and Atom feeds on their way
out of Statiq's Feeds pipeline — Statiq has no WebSub support and writes a
`rel=self` pointing at the site root, which would have subscribers asking the hub
about the home page. The same pair is in every page's `<head>` for a subscriber
that only has a page URL.

`deploy.ps1` and the CI workflow both ping the hub after the sync, never before:
the hub fetches the feed the moment it is told, and would cache the old one. A
hub that is down logs a warning; it does not fail a finished deploy.

The RDF feed is left alone — foreign-namespace elements inside an `rdf:channel`
risk upsetting strict parsers, and no WebSub subscriber asks for RSS 1.0.

### original-post-discovery and syndication

`announce.ps1` writes the URL of each copy back into the front matter (`Fedi:`).
`_post-after-content.cshtml` renders those as `u-syndication`, so anyone who finds
the copy on the fediverse can discover that this page is the original. The key
names in that template match `announce.ps1`'s target table on purpose: adding a
network is one row in each.

### post-type-discovery

A post is an article unless its front matter says otherwise. Any of these makes
it a reply, like, repost or bookmark, and renders a line of context above the
post as well as the `u-*` class that makes the type discoverable:

```
InReplyTo: https://example.com/their-post
InReplyToName: what they wrote about hedgehogs
LikeOf: https://example.com/something
RepostOf: https://example.com/something
BookmarkOf: https://example.com/something
```

Each takes a single URL or a list. The optional `...Name` companion is the link
text; without it the URL is the link text, which still tells a screen reader
where the link goes.

### fragmentions

`js/fragmention.js` makes a URL like `…/some-post.html#the+exact+words+quoted`
scroll to the first place those words appear, so anyone can link to a sentence
here without that sentence having needed an `id` in advance. It only fires when
the fragment does not match a real element id, and it moves focus to the phrase
rather than only scrolling — scrolling alone leaves a screen reader reading from
the top of the page. Matching is confined to a single text node, so a phrase
broken across a link or an `<em>` will not be found.

### What is deliberately not here

| Spec | Why not |
| --- | --- |
| **Micropub** | Needs a server that accepts POSTs and writes new posts. Nothing static can do this. Posts are Markdown files in `input/posts/`. |
| **Microsub** | A protocol for feed *readers* to talk to a server. It is not something a website implements. |
| **IndieAuth server** | Requires runtime code to issue and verify tokens. Delegated to indieauth.com instead, which is the whole point of the `rel` values above. |
| **Receiving webmentions directly** | Same reason: no POST endpoint. Delegated to webmention.io. |
| **Salmentions** | Requires *receiving* a webmention and then forwarding it upstream. Depends on the receiving half, which is not ours. |
| **Vouch** | An anti-spam extension for receivers. The receiving side is webmention.io's; adding the sender half alone buys nothing. |
| **h-event** | Nothing here is an event. The markup would be dead code with no post to exercise it. |
| **twtxt** | A separate plain-text copy of every post at a second URL, which is the [sidefile antipattern](https://indieweb.org/sidefile-antipattern) the IndieWeb principles argue against. The RSS, Atom and RDF feeds already cover "subscribe to this". |
| **XFN beyond rel=me** | Publishable, but there are no known consumers, and the extra `rel` values would be markup nobody reads. |

## Deployment

`.github/workflows/deploy.yml` runs on push to `main`, daily on a schedule (so
the links page stays fresh), and on manual dispatch. It builds, sanity-checks
the output, then `rclone sync`s `output/` to the server over SFTP.

### Deploying without GitHub

`./deploy.ps1` does the same thing from this machine, using your own SSH
credentials instead of the CI deploy key:

```
./deploy.ps1 -DryRun   # show what would change on the server
./deploy.ps1           # build and deploy
```

Both paths apply the same guards: refuse to deploy if the build produced no
`index.html` or fewer than 20 pages, pin the server's host key, and cap
deletions at 50 files.

Required repository secrets:

- `SFTP_KEY` — private half of an SSH keypair authorised for `fastfinge@interfree.ca`.
  Use a deploy-only key, not your personal one.
- `SFTP_KNOWN_HOSTS` — the server's host key, from `ssh-keyscan interfree.ca`.
- `FEDI_TOKEN` — Iceshrimp access token, `write:statuses` scope only. See
  "Announcing from CI". Optional: without it the announce step is skipped.

The workflow needs `contents: write` (declared in the file) so the announce step
can push the fediverse URLs back to `main`.

## Announcing posts

A post opts in by listing targets in its front matter:

```
Announce: fedi
```

or, once there is more than one:

```
Announce:
- fedi
- bluesky
```

Push it, and CI does the rest: it deploys, announces, commits the resulting URL
back, rebuilds, and redeploys. See "Announcing from CI" below. To do it by hand
instead:

```
./announce.ps1            # dry run: shows exactly what would be posted
./announce.ps1 -Publish   # actually post
```

`announce.ps1` is dry run by default and never touches a file unless `-Publish`
is passed. For each target it:

- skips the post if the target's URL key is already present (`fedi` records
  `Fedi:`), so re-running is safe
- refuses to announce a URL that is not live yet, so the link in the post always
  resolves — deploy first, then announce
- writes the resulting URL back into the front matter immediately, and if that
  write fails, prints the URL and stops rather than letting the next run post a
  duplicate

Set `FEDI_TOKEN` to an Iceshrimp access token with `write:statuses` scope.
`FEDI_INSTANCE` overrides the default of `https://fed.interfree.ca`.

Adding a network later means adding one entry to the `$Targets` table at the top
of the script: its front matter key, its token variable, and how to post.

The usual order for a new post is deploy, announce, deploy, `./webmention.ps1
-Send`. The second deploy picks up the new `Fedi:` value and wires up the comment
and reaction widgets; the webmentions go last because a receiver fetches the post
to verify the link, so the post has to be live and final first. CI runs that
whole sequence itself, so this order only matters when deploying by hand.

### Announcing from CI

`.github/workflows/deploy.yml` runs that sequence itself, in one job, in that
order and for those reasons:

1. build, sanity check, `rclone sync`
2. `./announce.ps1 -Publish` — after the deploy, because the script refuses to
   post a URL that is not live yet, and a fediverse post cannot be edited later
3. commit the new `Fedi:` values back to `main` with `[skip ci]`
4. rebuild and redeploy, so the comment widgets and the `u-syndication` link
   appear on the pages that were just published without them
5. ping the WebSub hub
6. `./webmention.ps1 -Send`, then commit `webmentions-sent.json` back

Steps 3 and 4 only run if something was actually announced. Steps 5 and 6 run
on every deploy, including the daily schedule run — both are no-ops when
nothing has changed, and step 6 has to see links that appear in a post edit,
not just in a new post.

Required repository secret:

- `FEDI_TOKEN` — an Iceshrimp access token with `write:statuses` scope. Without
  it the announce step logs that it is skipping and the deploy proceeds
  normally, so CI keeps working on a fork or before the secret is set.

The step that pushes the URLs back retries a rebase-and-push three times, and if
it still cannot push it fails the job and prints the commit diff into the log.
That matters: the URL is the only record that a post has already been announced,
so losing it means the next run posts a duplicate. Recover the `Fedi:` lines from
the log and commit them by hand.

Step 6 sends the webmentions, and it is last for the reason above: a receiver
fetches the source URL to verify the link, so the post has to be live *and*
final, rebuild included. It commits `webmentions-sent.json` back the same way
step 3 commits the `Fedi:` values, and for the same kind of reason — that file
is the only record of what has already been mentioned, so losing the push means
the next run mentions those links again. The send itself is
`continue-on-error`: the site is already live by then, and a receiver having a
bad day is not a failed deploy.

This was deliberately *not* in CI until the back catalogue had been mentioned
once, because the first run mentions every outbound link in every post and that
wants a human looking at the dry run first. `webmentions-sent.json` now covers
the archive, so there is no unattended first run left to worry about. If you
ever reset that file, run `./webmention.ps1` by hand and read the dry run before
letting CI near it again.

## A note on where this lives

Do not put a working copy inside iCloud Drive. iCloud evicts files to
placeholders, and Statiq aborts the entire build when a read times out
("The cloud operation was not completed before the time-out period expired"),
producing zero output files. It also leaves conflicted `filename 2.dll` copies
in `cache/`. Git and GitHub are the backup; a local path such as `D:\src\stuff`
is the place to work.
