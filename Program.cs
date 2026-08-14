using System;
using Devlead.Statiq.Themes;
using Statiq.App;
using Statiq.Common;
using Statiq.Web;

await Bootstrapper
    .Factory
    .CreateDefault(args)
    .AddThemeFromUri(new Uri("https://github.com/statiqdev/CleanBlog/archive/refs/heads/main.zip"))
    .AddWeb()
        .AddPipeline<WellKnownFolderPipeline>()
        .AddShortcode<LinkBlogShortcode>("LinkBlog")
        .AddShortcode<BookShortcode>("Book")
        // Statiq's feed generator knows nothing about WebSub and writes a
        // rel="self" pointing at the site root, and offers no hook for either.
        // Appending to the Feeds pipeline lets the finished XML be corrected on
        // its way out. See WebSubLinks.cs.
        .ModifyPipeline("Feeds", pipeline => pipeline.ProcessModules.Add(new WebSubLinks()))
    .RunAsync();
