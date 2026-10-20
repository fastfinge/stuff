using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using AngleSharp.Dom;
using AngleSharp.Html.Parser;
using Statiq.Common;
using Statiq.Core;
using IDocument = Statiq.Common.IDocument;

/// <summary>
/// Everything the build knows about this site as a standard.site publication on
/// AT Protocol: the AT-URI of each post's document record, the record itself, and
/// the .well-known file that ties the publication record to this domain.
/// </summary>
/// <remarks>
/// <para>
/// The build never talks to the PDS. Writing records is publish-time work, done
/// by standardsite.ps1 from the manifest this writes. Splitting it that way keeps
/// the build offline and repeatable, and keeps the thing that changes the outside
/// world in a script that dry-runs by default, like announce.ps1.
/// </para>
/// <para>
/// Record keys are derived, not assigned. Each post's key is a TID computed from
/// its Published date and its URL path, so the build can put the right
/// rel="site.standard.document" link in the page before the record exists, and
/// nothing has to be written back into front matter afterwards. It also means a
/// lost commit or a fresh clone can never publish a post twice: the same post
/// always lands on the same key, and the PDS itself is the record of what has been
/// published. Changing a post's date or filename changes its URL, and so its key;
/// standardsite.ps1 then publishes the new one and deletes the old.
/// </para>
/// </remarks>
public static class StandardSite
{
    public const string PublicationCollection = "site.standard.publication";
    public const string DocumentCollection = "site.standard.document";

    /// <summary>The settings.yml key holding the publication record's AT-URI.</summary>
    public const string PublicationKey = "StandardSitePublication";

    /// <summary>
    /// Where the manifest goes, relative to the project root. Deliberately not in
    /// output/: it is input to standardsite.ps1, not part of the site.
    /// </summary>
    public const string ManifestPath = "obj/standard-site.json";

    private const string TidAlphabet = "234567abcdefghijklmnopqrstuvwxyz";
    private const ulong MicrosecondsPerDay = 86_400_000_000;

    /// <summary>The publication's AT-URI, or null when standard.site is not configured.</summary>
    public static string? PublicationUri(IExecutionContext context)
    {
        string uri = context.GetString(PublicationKey);
        return string.IsNullOrWhiteSpace(uri) ? null : uri.Trim();
    }

    /// <summary>
    /// The AT-URI of a post's document record, or null for anything that is not a
    /// post, or when standard.site is not configured.
    /// </summary>
    public static string? DocumentUri(IDocument document, IExecutionContext context)
    {
        string? publication = PublicationUri(context);
        if (publication is null || !IsPost(document))
        {
            return null;
        }

        return $"at://{Did(publication)}/{DocumentCollection}/{DocumentKey(document)}";
    }

    public static bool IsPost(IDocument document) =>
        document.GetBool("IsPost") && !document.GetBool("IsPostArchive") && document.ContainsKey(WebKeys.Published);

    /// <summary>The URL path of a post, with the leading slash the lexicon asks for.</summary>
    public static string PathOf(IDocument document) => "/" + document.Destination.FullPath.TrimStart('/');

    /// <summary>
    /// Published as UTC. Dates in front matter carry no zone; reading them as UTC
    /// rather than local time keeps the record key identical on a Windows desktop
    /// and on a CI runner in a different time zone.
    /// </summary>
    public static DateTime PublishedUtc(IDocument document)
    {
        DateTime published = document.GetDateTime(WebKeys.Published);
        return published.Kind == DateTimeKind.Local
            ? published.ToUniversalTime()
            : DateTime.SpecifyKind(published, DateTimeKind.Utc);
    }

    /// <summary>
    /// A TID for the post: its Published timestamp, plus an offset under a day and
    /// a clock ID both taken from a hash of its path. Two posts on the same date
    /// get different keys, and the key still sorts by date.
    /// </summary>
    public static string DocumentKey(IDocument document)
    {
        byte[] hash = SHA256.HashData(Encoding.UTF8.GetBytes(PathOf(document)));
        ulong offset = BitConverter.ToUInt64(hash, 0) % MicrosecondsPerDay;
        ulong clockId = BitConverter.ToUInt64(hash, 8) & 0x3FF;

        ulong micros = (ulong)(PublishedUtc(document) - DateTime.UnixEpoch).Ticks / 10 + offset;
        return EncodeTid((micros << 10) | clockId);
    }

    /// <summary>
    /// 13 characters of base32-sortable, five bits each, most significant first.
    /// The top bit of a TID is always zero, which a timestamp in microseconds
    /// leaves clear for the next few hundred thousand years.
    /// </summary>
    private static string EncodeTid(ulong value)
    {
        char[] chars = new char[13];
        for (int i = chars.Length - 1; i >= 0; i--)
        {
            chars[i] = TidAlphabet[(int)(value & 0x1F)];
            value >>= 5;
        }
        return new string(chars);
    }

    /// <summary>The DID out of at://did/collection/rkey.</summary>
    public static string Did(string atUri) => atUri["at://".Length..].Split('/')[0];

    /// <summary>The record key out of at://did/collection/rkey.</summary>
    public static string Rkey(string atUri) => atUri[(atUri.LastIndexOf('/') + 1)..];

    /// <summary>
    /// The publication URL as the lexicon wants it: no trailing slash, because a
    /// document's canonical URL is this joined to a path that starts with one.
    /// </summary>
    public static string SiteUrl(IExecutionContext context) => context.GetLink("/", true).TrimEnd('/');

    /// <summary>
    /// Plain text of a rendered post body, with a blank line between blocks and a
    /// line break per list item, table row and br. The lexicon wants textContent
    /// free of markup, and taking it from the rendered page rather than the
    /// Markdown means shortcodes have already been expanded into what a reader
    /// actually sees.
    /// </summary>
    public static string PlainText(IElement root)
    {
        StringBuilder text = new();
        AppendText(root, text);

        // Collapse the runs of blank lines that nested blocks leave behind.
        List<string> lines = new();
        foreach (string line in text.ToString().Split('\n').Select(x => x.TrimEnd()))
        {
            if (line.Trim().Length == 0 && (lines.Count == 0 || lines[^1].Length == 0))
            {
                continue;
            }
            lines.Add(line.Trim().Length == 0 ? string.Empty : line);
        }
        return string.Join('\n', lines).Trim();
    }

    private static readonly HashSet<string> BlockElements = new(StringComparer.OrdinalIgnoreCase)
    {
        "address", "article", "aside", "blockquote", "dd", "details", "div", "dl", "dt",
        "figcaption", "figure", "footer", "h1", "h2", "h3", "h4", "h5", "h6", "header",
        "hr", "main", "nav", "ol", "p", "pre", "section", "summary", "table", "ul"
    };

    private static readonly HashSet<string> LineElements = new(StringComparer.OrdinalIgnoreCase)
    {
        "br", "li", "tr"
    };

    private static readonly HashSet<string> SkippedElements = new(StringComparer.OrdinalIgnoreCase)
    {
        "script", "style", "template", "noscript"
    };

    private static void AppendText(INode node, StringBuilder text)
    {
        foreach (INode child in node.ChildNodes)
        {
            if (child is IText t)
            {
                // Inside <pre> whitespace is content; everywhere else it is layout.
                if (child.ParentElement?.Closest("pre") is not null)
                {
                    text.Append(t.Data);
                    continue;
                }
                string collapsed = CollapseWhitespace(t.Data);
                text.Append(text.Length == 0 || text[^1] == '\n' ? collapsed.TrimStart() : collapsed);
                continue;
            }
            if (child is not IElement element || SkippedElements.Contains(element.LocalName))
            {
                continue;
            }

            bool block = BlockElements.Contains(element.LocalName);
            bool line = LineElements.Contains(element.LocalName);
            if (block)
            {
                text.Append("\n\n");
            }
            else if (line)
            {
                text.Append('\n');
            }

            AppendText(element, text);

            if (block)
            {
                text.Append("\n\n");
            }
        }
    }

    private static string CollapseWhitespace(string value)
    {
        StringBuilder result = new(value.Length);
        bool space = false;
        foreach (char c in value)
        {
            if (char.IsWhiteSpace(c))
            {
                if (!space)
                {
                    result.Append(' ');
                }
                space = true;
            }
            else
            {
                result.Append(c);
                space = false;
            }
        }
        return result.ToString();
    }
}

/// <summary>
/// Writes obj/standard-site.json: the publication record and every post's
/// document record, exactly as standardsite.ps1 should find them on the PDS.
/// Attached to the end of the Content pipeline from Program.cs, where each post
/// has been through its layout and the text can be read out of its e-content.
/// </summary>
public class StandardSiteManifest : Module
{
    protected override async Task<IEnumerable<IDocument>> ExecuteContextAsync(IExecutionContext context)
    {
        string? publication = StandardSite.PublicationUri(context);
        if (publication is null)
        {
            return context.Inputs;
        }

        HtmlParser parser = new();
        List<object> documents = new();

        foreach (IDocument input in context.Inputs.Where(StandardSite.IsPost).OrderBy(x => x.Destination.FullPath))
        {
            string html = await input.GetContentStringAsync();
            using AngleSharp.Html.Dom.IHtmlDocument page = parser.ParseDocument(html);
            IElement? body = page.QuerySelector(".e-content");
            if (body is null)
            {
                // Without the body there is no textContent, and an empty one would
                // overwrite the real text on the PDS. Leave this post out and say so.
                context.LogWarning(input, "standard.site: no .e-content in the rendered post; left out of the manifest.");
                continue;
            }

            Dictionary<string, object> record = new()
            {
                ["$type"] = StandardSite.DocumentCollection,
                ["site"] = publication,
                ["path"] = StandardSite.PathOf(input),
                ["title"] = input.GetTitle(),
                ["publishedAt"] = StandardSite.PublishedUtc(input).ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'"),
                ["textContent"] = StandardSite.PlainText(body),
            };

            string description = input.GetString("Lead") ?? input.GetString(WebKeys.Description);
            if (!string.IsNullOrWhiteSpace(description))
            {
                record["description"] = description.Trim();
            }

            // The lexicon says tags are bare words: no leading # and at most 128
            // graphemes, which no real tag here comes near.
            string[] tags = (input.GetList<string>("Tags") ?? Array.Empty<string>())
                .Select(x => x.Trim().TrimStart('#'))
                .Where(x => x.Length > 0)
                .Distinct()
                .ToArray();
            if (tags.Length > 0)
            {
                record["tags"] = tags;
            }

            documents.Add(new
            {
                rkey = StandardSite.DocumentKey(input),
                uri = StandardSite.DocumentUri(input, context),
                record,
            });
        }

        var manifest = new
        {
            publication = new
            {
                uri = publication,
                rkey = StandardSite.Rkey(publication),
                did = StandardSite.Did(publication),
                record = new Dictionary<string, object>
                {
                    ["$type"] = StandardSite.PublicationCollection,
                    ["url"] = StandardSite.SiteUrl(context),
                    ["name"] = context.GetString("SiteTitle"),
                    ["description"] = context.GetString("SiteDescription"),
                    ["preferences"] = new Dictionary<string, object> { ["showInDiscover"] = true },
                },
            },
            documents,
        };

        string path = context.FileSystem.RootPath.Combine(StandardSite.ManifestPath).FullPath;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        await File.WriteAllTextAsync(
            path,
            JsonSerializer.Serialize(manifest, new JsonSerializerOptions
            {
                WriteIndented = true,
                // Keep apostrophes and non-ASCII readable in the file; it is only
                // ever read back as JSON, never embedded in HTML.
                Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
            }),
            new UTF8Encoding(false),
            context.CancellationToken);

        context.LogInformation(null, $"standard.site: wrote {documents.Count} document records to {StandardSite.ManifestPath}");
        return context.Inputs;
    }
}

/// <summary>
/// Emits /.well-known/site.standard.publication, whose whole body is the
/// publication record's AT-URI. That is how a reader of the record confirms this
/// domain really is the publication's home.
/// </summary>
public class StandardSitePublicationPipeline : Pipeline
{
    public StandardSitePublicationPipeline()
    {
        OutputModules = new ModuleList
        {
            new ExecuteConfig(Config.FromContext(context =>
            {
                string? uri = StandardSite.PublicationUri(context);
                return uri is null
                    ? Array.Empty<IDocument>()
                    : context.CreateDocument(
                        new NormalizedPath(".well-known/site.standard.publication"),
                        context.GetContentProvider(uri, "text/plain")).Yield();
            })),
            new WriteFiles(),
        };
    }
}
