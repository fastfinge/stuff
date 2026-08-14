using System.Xml.Linq;
using Statiq.Common;

/// <summary>
/// Adds the WebSub discovery pair -- rel="hub" and rel="self" -- to the generated
/// RSS and Atom feeds, and corrects the rel="self" Statiq writes.
/// </summary>
/// <remarks>
/// <para>
/// WebSub is how a subscriber finds out about a new post in seconds instead of
/// whenever it next decides to poll. It works by the subscriber reading two links
/// off the feed: the hub to subscribe at, and the feed's own URL to name as the
/// topic. Statiq's feed generator emits neither -- its Atom rel="self" points at
/// the site root rather than at the feed -- and exposes no hook for adding them,
/// so the finished XML is edited on the way out of the Feeds pipeline. See
/// Program.cs for where this is attached.
/// </para>
/// <para>
/// RDF is left alone. The hub links would have to sit inside an rdf:channel,
/// where a foreign namespace risks upsetting strict RDF parsers, and no WebSub
/// subscriber asks for an RSS 1.0 feed anyway.
/// </para>
/// </remarks>
public class WebSubLinks : Module
{
    private static readonly XNamespace Atom = "http://www.w3.org/2005/Atom";
    private static readonly XNamespace Rss10 = "http://purl.org/rss/1.0/";

    protected override async Task<IEnumerable<IDocument>> ExecuteInputAsync(
        IDocument input,
        IExecutionContext context)
    {
        string hub = context.GetString("WebSubHub");
        if (string.IsNullOrWhiteSpace(hub))
        {
            return input.Yield();
        }

        XDocument feed;
        try
        {
            await using Stream stream = input.GetContentStream();
            feed = await XDocument.LoadAsync(stream, LoadOptions.PreserveWhitespace, context.CancellationToken);
        }
        catch (Exception ex)
        {
            // A feed that cannot be parsed is a bug worth seeing, but it is still
            // a valid feed to everyone downstream; ship it as generated.
            context.LogWarning(input, $"WebSub: could not parse the feed to add hub links: {ex.Message}");
            return input.Yield();
        }

        XElement? root = feed.Root;
        if (root is null)
        {
            return input.Yield();
        }

        string selfUrl = context.GetLink(input, true);

        if (root.Name == Atom + "feed")
        {
            AddAtomLinks(root, hub, selfUrl, "application/atom+xml", "entry");
        }
        else if (root.Name == "rss")
        {
            XElement? channel = root.Element("channel");
            if (channel is null)
            {
                return input.Yield();
            }

            // RSS 2.0 has no link element that can carry a rel, so the pair goes
            // in as Atom elements, which is what every WebSub hub looks for.
            root.SetAttributeValue(XNamespace.Xmlns + "atom", Atom.NamespaceName);
            AddAtomLinks(channel, hub, selfUrl, "application/rss+xml", "item");
        }
        else if (root.Name == Rss10 + "RDF" || root.Name.LocalName == "RDF")
        {
            return input.Yield();
        }
        else
        {
            context.LogWarning(input, $"WebSub: unrecognised feed root <{root.Name.LocalName}>; left unchanged.");
            return input.Yield();
        }

        // XDocument.ToString drops the declaration, and writing through an
        // XmlWriter over a StringBuilder would claim utf-16 in it.
        string xml = (feed.Declaration?.ToString() ?? "<?xml version=\"1.0\" encoding=\"utf-8\"?>")
            + "\n"
            + feed.ToString(SaveOptions.DisableFormatting);

        return input
            .Clone(context.GetContentProvider(xml, input.ContentProvider.MediaType))
            .Yield();
    }

    private static void AddAtomLinks(XElement parent, string hub, string selfUrl, string mediaType, string itemName)
    {
        // Statiq writes an Atom rel="self" pointing at the site root. A subscriber
        // that trusted it would ask the hub to notify it about the home page, so
        // the wrong one goes before the right one is added.
        parent
            .Elements(Atom + "link")
            .Where(x => (string?)x.Attribute("rel") is "self" or "hub")
            .Remove();

        object[] links =
        {
            new XElement(Atom + "link",
                new XAttribute("rel", "self"),
                new XAttribute("type", mediaType),
                new XAttribute("href", selfUrl)),
            new XText("\n\t\t"),
            new XElement(Atom + "link",
                new XAttribute("rel", "hub"),
                new XAttribute("href", hub)),
            new XText("\n\t\t")
        };

        // Metadata about the feed belongs above the posts, not tacked on after the
        // last one. Atom and RSS both allow either, but a reader opening the file
        // should find these where the rest of the feed's own details are.
        XElement? firstItem = parent.Elements().FirstOrDefault(x => x.Name.LocalName == itemName);
        if (firstItem is null)
        {
            parent.Add(links);
        }
        else
        {
            firstItem.AddBeforeSelf(links);
        }
    }
}
