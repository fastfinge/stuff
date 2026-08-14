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

Then:

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

The usual order for a new post is deploy, announce, deploy — the second deploy
picks up the new `Fedi:` value and wires up the comment and reaction widgets.

## A note on where this lives

Do not put a working copy inside iCloud Drive. iCloud evicts files to
placeholders, and Statiq aborts the entire build when a read times out
("The cloud operation was not completed before the time-out period expired"),
producing zero output files. It also leaves conflicted `filename 2.dll` copies
in `cache/`. Git and GitHub are the backup; a local path such as `D:\src\stuff`
is the place to work.
