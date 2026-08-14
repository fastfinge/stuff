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

Required repository secrets:

- `SFTP_KEY` — private half of an SSH keypair authorised for `fastfinge@interfree.ca`.
  Use a deploy-only key, not your personal one.
- `SFTP_KNOWN_HOSTS` — the server's host key, from `ssh-keyscan interfree.ca`.

## A note on where this lives

Do not put a working copy inside iCloud Drive. iCloud evicts files to
placeholders, and Statiq aborts the entire build when a read times out
("The cloud operation was not completed before the time-out period expired"),
producing zero output files. It also leaves conflicted `filename 2.dll` copies
in `cache/`. Git and GitHub are the backup; a local path such as `D:\src\stuff`
is the place to work.
