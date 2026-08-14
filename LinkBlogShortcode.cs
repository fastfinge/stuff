using System.Globalization;
using System.Net;
using System.Xml.Linq;
using Statiq.Common;

/// <summary>
/// Renders the linkblog feed as a list. Replaces the external tinyfeed.exe binary.
/// Usage in a content file: &lt;?# LinkBlog /?&gt;
/// Optional arguments: Feed (url), Count (max items).
/// </summary>
public class LinkBlogShortcode : Shortcode
{
    private const string DefaultFeed = "https://stream.interfree.ca/posts-rss";
    private const int DefaultCount = 50;

    // The linkblog emits "15 Aug 26 14:40 UTC": RFC 822 with no weekday and a
    // two-digit year, which the general parser does not reliably handle.
    private static readonly string[] DateFormats =
    {
        "dd MMM yy HH:mm UTC",
        "dd MMM yyyy HH:mm UTC",
        "ddd, dd MMM yyyy HH:mm:ss zzz",
        "ddd, dd MMM yyyy HH:mm:ss Z"
    };

    public override async Task<ShortcodeResult> ExecuteAsync(
        KeyValuePair<string, string>[] args,
        string content,
        IDocument document,
        IExecutionContext context)
    {
        IMetadataDictionary arguments = args.ToDictionary("Feed", "Count");
        string feedUrl = arguments.GetString("Feed", DefaultFeed);
        int count = arguments.GetInt("Count", DefaultCount);

        XDocument feed;
        try
        {
            using HttpResponseMessage response = await context.SendHttpRequestWithRetryAsync(feedUrl);
            response.EnsureSuccessStatusCode();
            await using Stream stream = await response.Content.ReadAsStreamAsync();
            feed = await XDocument.LoadAsync(stream, LoadOptions.None, context.CancellationToken);
        }
        catch (Exception ex)
        {
            // A flaky linkblog should not take down the whole site build.
            context.LogWarning(document, $"Could not fetch linkblog feed {feedUrl}: {ex.Message}");
            return "<p>The links feed could not be loaded.</p>";
        }

        List<string> items = new();
        foreach (XElement item in feed.Descendants("item").Take(count))
        {
            string title = (string?)item.Element("title") ?? "Untitled";
            string link = ((string?)item.Element("link") ?? string.Empty).Trim();
            if (link.Length == 0)
            {
                continue;
            }

            string date = FormatDate((string?)item.Element("pubDate"));
            string source = SourceName(link);

            string heading = $"<a href=\"{WebUtility.HtmlEncode(link)}\">{WebUtility.HtmlEncode(title)}</a>";
            string meta = date.Length > 0
                ? $"<time datetime=\"{date}\">{date}</time> &middot; {WebUtility.HtmlEncode(source)}"
                : WebUtility.HtmlEncode(source);

            items.Add($"  <li>{heading}<br><small>{meta}</small></li>");
        }

        if (items.Count == 0)
        {
            return "<p>No links yet.</p>";
        }

        context.LogInformation(document, $"Linkblog: rendered {items.Count} item(s) from {feedUrl}");
        return $"<ul class=\"linkblog\">\n{string.Join("\n", items)}\n</ul>";
    }

    private static string FormatDate(string? pubDate)
    {
        if (string.IsNullOrWhiteSpace(pubDate))
        {
            return string.Empty;
        }

        pubDate = pubDate.Trim();
        if (DateTimeOffset.TryParseExact(pubDate, DateFormats, CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal, out DateTimeOffset parsed)
            || DateTimeOffset.TryParse(pubDate, CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal, out parsed))
        {
            return parsed.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        }

        return string.Empty;
    }

    private static string SourceName(string link) =>
        Uri.TryCreate(link, UriKind.Absolute, out Uri? uri)
            ? uri.Host.StartsWith("www.", StringComparison.OrdinalIgnoreCase) ? uri.Host[4..] : uri.Host
            : string.Empty;
}
