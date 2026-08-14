using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Statiq.Common;

/// <summary>
/// Renders a book as cover art, title and author, linked to its Open Library page
/// so readers can pick their own library or bookshop rather than being sent to one.
/// Replaces the Open Library iframe widget, which is a separate unlabelled document
/// to a screen reader and cannot be styled or read without a live network.
/// Usage in a content file: &lt;?# Book OL42557111W /?&gt;
/// Optional arguments: Title, Author, Cover, Size (S, M or L).
/// </summary>
public class BookShortcode : Shortcode
{
    private const string CoverBaseUrl = "https://covers.openlibrary.org/b/id";

    // Works are OL...W and editions OL...M. Matching anywhere in the argument means a
    // pasted Open Library URL works as well as a bare ID.
    private static readonly Regex IdPattern =
        new(@"OL\d+[WM]", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public override async Task<ShortcodeResult> ExecuteAsync(
        KeyValuePair<string, string>[] args,
        string content,
        IDocument document,
        IExecutionContext context)
    {
        IMetadataDictionary arguments = args.ToDictionary("Id", "Title", "Author", "Cover", "Size");
        string rawId = arguments.GetString("Id", string.Empty);

        Match match = IdPattern.Match(rawId);
        if (!match.Success)
        {
            context.LogWarning(
                document,
                $"Book: \"{rawId}\" is not an Open Library work (OL...W) or edition (OL...M) ID.");
            return string.Empty;
        }

        string id = match.Value.ToUpperInvariant();
        bool isEdition = id.EndsWith('M');
        string pageUrl = isEdition
            ? $"https://openlibrary.org/books/{id}"
            : $"https://openlibrary.org/works/{id}";
        string size = SizeCode(arguments.GetString("Size", "L"));

        Book? book = await FetchAsync(id, isEdition, context, document);

        // Explicit arguments win, so a post can correct or supply what Open Library lacks.
        string title = FirstNonEmpty(arguments.GetString("Title", string.Empty), book?.Title, id);
        string author = FirstNonEmpty(arguments.GetString("Author", string.Empty), book?.Author);
        // Plenty of self-published books are catalogued with no cover at all, so a post can
        // point at its own image instead.
        string coverUrl = FirstNonEmpty(
            arguments.GetString("Cover", string.Empty),
            book?.CoverId is int coverId ? $"{CoverBaseUrl}/{coverId}-{size}.jpg" : null);

        return Render(pageUrl, title, author, book?.FirstPublished, coverUrl);
    }

    private static string Render(string pageUrl, string title, string author, int? firstPublished, string coverUrl)
    {
        string href = WebUtility.HtmlEncode(pageUrl);
        StringBuilder html = new();

        // Two vocabularies over one set of elements: schema.org for search engines,
        // microformats2 for IndieWeb readers. h-cite is the mf2 way to say "this is a
        // thing I am citing, and here is what it is", which is what a book in a review
        // is; it nests inside the post's h-entry as a child rather than a property.
        html.Append("<div class=\"booksnip h-cite\" itemscope itemtype=\"https://schema.org/Book\">");

        if (coverUrl.Length > 0)
        {
            // The cover repeats the title and author sitting beside it, so it is decorative:
            // empty alt, and the link around it is hidden from assistive technology and the
            // tab order rather than being offered a second time.
            html.Append($"<a class=\"booksnip-cover\" href=\"{href}\" tabindex=\"-1\" aria-hidden=\"true\">")
                .Append($"<img class=\"u-photo\" src=\"{WebUtility.HtmlEncode(coverUrl)}\" alt=\"\" itemprop=\"image\" loading=\"lazy\" decoding=\"async\">")
                .Append("</a>");
        }

        html.Append("<div class=\"booksnip-detail\">")
            .Append($"<p class=\"booksnip-title\"><a class=\"u-url\" href=\"{href}\" itemprop=\"sameAs\">")
            .Append($"<cite class=\"p-name\" itemprop=\"name\">{WebUtility.HtmlEncode(title)}</cite>")
            .Append("<span class=\"visually-hidden\"> on Open Library</span></a></p>");

        if (author.Length > 0)
        {
            html.Append("<p class=\"booksnip-byline\">by ")
                .Append("<span class=\"p-author h-card\" itemprop=\"author\" itemscope itemtype=\"https://schema.org/Person\">")
                .Append($"<span class=\"p-name\" itemprop=\"name\">{WebUtility.HtmlEncode(author)}</span></span></p>");
        }

        if (firstPublished is int year)
        {
            html.Append($"<p class=\"booksnip-meta\">First published {year}</p>");
        }

        html.Append("</div></div>");
        return html.ToString();
    }

    private static async Task<Book?> FetchAsync(string id, bool isEdition, IExecutionContext context, IDocument document)
    {
        // One search call covers both kinds of ID and returns the author names, which the
        // works endpoint only gives as keys that would each need a further request.
        string query = isEdition ? $"edition_key:{id}" : $"key:/works/{id}";
        string url = "https://openlibrary.org/search.json"
            + $"?q={Uri.EscapeDataString(query)}"
            + "&fields=title,author_name,first_publish_year,cover_i&limit=1";

        try
        {
            using HttpResponseMessage response = await context.SendHttpRequestWithRetryAsync(url);
            response.EnsureSuccessStatusCode();
            await using Stream stream = await response.Content.ReadAsStreamAsync();
            using JsonDocument json = await JsonDocument.ParseAsync(stream, default, context.CancellationToken);

            if (!json.RootElement.TryGetProperty("docs", out JsonElement docs)
                || docs.GetArrayLength() == 0)
            {
                context.LogWarning(document, $"Book: Open Library has no record of {id}.");
                return null;
            }

            JsonElement doc = docs[0];
            return new Book(
                doc.TryGetProperty("title", out JsonElement t) ? t.GetString() ?? string.Empty : string.Empty,
                JoinAuthors(doc),
                doc.TryGetProperty("first_publish_year", out JsonElement y) && y.TryGetInt32(out int year) ? year : null,
                doc.TryGetProperty("cover_i", out JsonElement c) && c.TryGetInt32(out int cover) ? cover : null);
        }
        catch (Exception ex)
        {
            // A flaky Open Library should not take down the whole site build; the link to
            // the book still renders, just without the cover and the fetched details.
            context.LogWarning(document, $"Book: could not look up {id}: {ex.Message}");
            return null;
        }
    }

    private static string JoinAuthors(JsonElement doc)
    {
        if (!doc.TryGetProperty("author_name", out JsonElement authors) || authors.ValueKind != JsonValueKind.Array)
        {
            return string.Empty;
        }

        List<string> names = new();
        foreach (JsonElement author in authors.EnumerateArray())
        {
            string? name = author.GetString();
            if (!string.IsNullOrWhiteSpace(name))
            {
                names.Add(name.Trim());
            }
        }

        return names.Count switch
        {
            0 => string.Empty,
            1 => names[0],
            2 => $"{names[0]} and {names[1]}",
            _ => $"{string.Join(", ", names.Take(names.Count - 1))} and {names[^1]}"
        };
    }

    private static string SizeCode(string size) =>
        size.Trim().ToUpperInvariant() switch
        {
            "S" or "SMALL" => "S",
            "M" or "MEDIUM" => "M",
            _ => "L"
        };

    private static string FirstNonEmpty(params string?[] values) =>
        values.FirstOrDefault(v => !string.IsNullOrWhiteSpace(v))?.Trim() ?? string.Empty;

    private sealed record Book(string Title, string Author, int? FirstPublished, int? CoverId);
}
