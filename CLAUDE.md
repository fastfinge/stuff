# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

The source for [stuff.interfree.ca](https://stuff.interfree.ca), a personal blog. It is a
[Statiq Web](https://statiq.dev) site, which means it is a .NET 10 console app (`Program.cs`)
whose "output" is a static site in `output/`. Content lives in `input/`.

The author is blind and uses a screen reader. Accessibility of generated markup is a
first-order concern, not a nice-to-have — prefer semantic HTML, meaningful link text, and
correct heading structure over visual-only solutions.

## Commands

```
dotnet run                      # build the site into output/
dotnet run -- preview           # build and serve at http://localhost:5080
dotnet build                    # compile only; fast syntax check for C# shortcode work
./deploy.ps1 -DryRun            # show what a deploy would change on the server
./deploy.ps1                    # build and deploy from this machine
./announce.ps1                  # dry run: show what would be posted to the fediverse
./announce.ps1 -Publish         # actually post
./webmention.ps1                # dry run: show what webmentions would be sent
./webmention.ps1 -Send          # actually send them
```

There is no test suite and no linter. Verification is: build, then inspect the generated
HTML in `output/`. To exercise a shortcode or template change, drop a temporary page in
`input/pages/`, run `dotnet run`, read the corresponding `output/pages/*.html`, then delete
both. `dotnet build` emits ~30 `NU19xx` vulnerability warnings from Statiq's transitive
dependencies; those are pre-existing noise, not something a change introduced.

## Architecture

**The theme is downloaded, not checked in.** `Program.cs` calls `AddThemeFromUri` against a
GitHub zip of [CleanBlog](https://github.com/statiqdev/CleanBlog), which unpacks into
`theme/` (gitignored) at build time. Files in `input/` **shadow** same-named files in
`theme/main/CleanBlog-main/input/`. That is the entire override mechanism — `_layout.cshtml`,
`_head.cshtml`, and `_navigation.cshtml` at the top of `input/` are local replacements of
theme files. Read the theme copy before editing an override; the theme file is the baseline
being diverged from.

**Post URLs come from front matter, not folders.** `input/posts/_directory.yml` computes
`DestinationPath` from each post's `Published` date, so a post at
`input/posts/2025/04/24/slug.md` publishes to `/2025/04/24/slug.html` because of the date in
its front matter. Keeping the folders in step is a convention for finding files, nothing
more. That rule carries a guard for `IsPostArchive` — see the comment in the file before
touching it; removing the guard moves the "Posts" nav target on every deploy.

**Shortcodes are C# classes at the repo root**, implementing `Statiq.Common.Shortcode` and
registered by name in `Program.cs`:

- `LinkBlogShortcode.cs` → `<?# LinkBlog /?>`, renders an external RSS feed as a list
- `BookShortcode.cs` → `<?# Book OL42557111W /?>`, renders a book from the Open Library API

Both fetch over HTTP **at build time** via `context.SendHttpRequestWithRetryAsync` and emit
plain static HTML — no third-party iframes or JavaScript reach the reader. Follow that
pattern: a remote service being down must log a warning and degrade (fallback markup, or a
plain link), never throw and take the whole build with it.

**Site-wide settings** are in `settings.yml`. Three entries encode facts rather than
preferences: `LinkHideIndexPages: false` exists because the web server has no directory
index, `CommentEngine: "fediverse"` makes the theme's `_post-comments.cshtml` dispatcher
load the local `input/_post-comments-fediverse.cshtml`, and `MirrorResources: false` is
there because the module is broken — see Gotchas. The `Identity` and `IndieWeb`
blocks hold every endpoint and account URL the IndieWeb markup uses; templates read them
from there rather than hardcoding.

**The microformats markup is load-bearing and easy to break by accident.** README.md has
the full picture; the parts that constrain edits:

- The `h-entry` (post) and `h-feed` (archive) roots open in `_layout.cshtml` *before* the
  masthead partial and close *after* the content, because `_header.cshtml` is where the
  name, date, author and tags are. They are emitted with `Html.Raw` because Razor demands
  balanced markup inside a code block. Comments render in their own container after the
  root closes — moving them back inside would make replies part of the post's content.
- `e-content` wraps `@RenderBody()` only, not the syndication links after it.
- `input/_header.cshtml`, `input/_post.cshtml` and `input/posts/index.cshtml` are copies
  of theme files that exist *only* to carry these classes. Diff against the theme copy
  before editing; the theme file is the baseline. (`input/search.cshtml` is also a theme
  copy, but for a different reason — see MirrorResources under Gotchas.)
- The footer h-card in `_copyright.cshtml` is the site's representative h-card. Its
  `u-url`, `u-uid` and `rel=me` must all resolve to the home page or it stops being one.
- Verify with a parser, not by eye: `pip install mf2py`, then parse a page from `output/`.
  README.md has the one-liner.

**Anything that must happen at publish time is a script, not a build step.** `announce.ps1`
posts to the fediverse, `webmention.ps1` sends webmentions for outbound links, and
`deploy.ps1` pings the WebSub hub after the sync. Ordering is a correctness constraint for
all three — see the Gotchas below.

## Gotchas

**Razor eats `@`.** In any `.cshtml` file, a literal `@` must be written `@@`. This
previously broke on `@media` in generated CSS. Site-specific CSS lives in the inline
`<style>` block in `input/_head.cshtml`; write it without `@`-rules where possible (e.g.
`flex-wrap` instead of a breakpoint) rather than relying on remembering to escape.

**`deploy.ps1` and `.github/workflows/deploy.yml` do the same job and must not drift.** Both
refuse to deploy unless `output/index.html` exists and there are ≥20 HTML pages, both pin the
server's SSH host key, and both cap `rclone` deletions at 50 files. A change to one belongs in
the other. `deploy.ps1` additionally clears `output/` first, because Statiq leaves behind
pages whose source was deleted and `rclone sync` would push them live; CI avoids this by
building from a fresh checkout.

**Publishing has an ordering requirement.** `announce.ps1` refuses to announce a URL that is
not live yet, and writes the resulting post URL back into front matter (`Fedi:`), which is
what the comment and reaction widgets and the `u-syndication` link read. `webmention.ps1`
comes last, because a receiver fetches the source URL to verify the link really exists. So
the sequence for a new post is deploy, announce, deploy, `./webmention.ps1 -Send`.

CI does that whole sequence itself, in one job, in that order — deploy, announce, commit the
`Fedi:` values back to `main` with `[skip ci]`, rebuild, redeploy. Do not reorder those
steps to "save a build": announcing before the deploy posts a permanent, uneditable
fediverse link to a URL that 404s, and skipping the rebuild leaves the just-published post
without its comment widgets. The commit-back is gated on `git diff --name-only --
input/posts`, so everything after it is skipped when nothing was announced. `webmention.ps1`
runs last, after the redeploy, and commits `webmentions-sent.json` back the same way — a
receiver fetches the source URL to verify the link, so the post must be live and final
before it runs.

**`webmention.ps1` sends the whole back catalogue on its first real run.** It considers
every outbound link in every post, minus what `webmentions-sent.json` records. That file is
the only thing stopping a re-send, so it belongs in git — and now that CI runs the send
unattended, an emptied or unpushed state file means CI re-mentions the archive. If you ever
reset it, look at the dry run by hand before letting CI near it.

**Syntax highlighting is client-side and fully self-hosted.** All 298 Prism 1.29.0 language
grammars live in `input/js/vendor/prism-components/`, and `input/_layout.cshtml` points the
autoloader at them with `data-autoloader-path`. Do not "tidy up" that directory to only the
languages currently in use: the autoloader fetches a grammar the first time a language
appears, and a missing file fails silently as unhighlighted code. Upgrading Prism means
re-downloading all of them at the matching version, along with `prism-core.min.js`,
`prism-autoloader.min.js` and `prism.css` in `input/js/vendor/`.

**Do not turn `MirrorResources` back on.** It rewrites CDN URLs to local copies by
round-tripping every page through an HTML parser, and that round-trip double-encodes
entities in attribute values: `?id=x&hl=en_US` became `?id=x&amp;hl=en_US` (a parameter
called `amp;hl`), and `Sam's Stuff` became `Sam&#x27;s Stuff` in the `og:` tags and the feed
link titles. The assets it used to fetch are vendored in `input/js/vendor/` instead, so it
has nothing left to do. `input/_layout.cshtml` and `input/search.cshtml` point at those
local copies; the theme's copies of both point at jsdelivr, so do not "restore" those lines
when diffing against the theme.

**`WebSubLinks.cs` edits Statiq's finished feed XML.** It is attached to the built-in
`Feeds` pipeline from `Program.cs` via `ModifyPipeline`, because `GenerateFeeds` has no hub
support and no hook. If a Statiq upgrade renames that pipeline or changes the feed shape,
this is what breaks; it warns and passes the feed through unchanged rather than failing the
build.

**Do not put a working copy in iCloud Drive.** iCloud evicts files to placeholders and Statiq
aborts the whole build on a read timeout, producing zero output. Work from a local path.
