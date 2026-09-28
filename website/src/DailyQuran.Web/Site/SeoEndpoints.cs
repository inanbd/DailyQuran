using System.Text;
using System.Xml;
using DailyQuran.Web.Quran;
using Microsoft.Extensions.Options;

namespace DailyQuran.Web.Site;

/// <summary>
/// What search engines ask for: a sitemap of every page worth finding — each
/// surah in each translation, and each ayah on its own — and a robots.txt that
/// points to it.
/// </summary>
public static class SeoEndpoints
{
    private static readonly string[] Pages = ["/", "/features", "/quran", "/contact", "/privacy", "/sources"];

    private const string SitemapNamespace = "http://www.sitemaps.org/schemas/sitemap/0.9";

    public static IEndpointRouteBuilder MapSeoEndpoints(this IEndpointRouteBuilder endpoints)
    {
        // An index of three, so each list stays well inside the 50,000 a
        // sitemap may hold, and Search Console reports on each separately.
        endpoints.MapGet("/sitemap.xml", (HttpRequest request, IOptionsSnapshot<SiteOptions> site) =>
            Xml(xml =>
            {
                xml.WriteStartElement("sitemapindex", SitemapNamespace);
                foreach (string part in new[] { "pages", "surahs", "ayat" })
                {
                    xml.WriteStartElement("sitemap");
                    xml.WriteElementString("loc", site.Value.AbsoluteUrl(request, $"/sitemap-{part}.xml"));
                    xml.WriteEndElement();
                }
                xml.WriteEndElement();
            }));

        endpoints.MapGet("/sitemap-pages.xml", (HttpRequest request, IOptionsSnapshot<SiteOptions> site) =>
            UrlSet(Pages, request, site.Value));

        // Every surah in every edition: each translation is a page of its own.
        endpoints.MapGet("/sitemap-surahs.xml", (HttpRequest request, QuranLibrary library, IOptionsSnapshot<SiteOptions> site) =>
            UrlSet(
                library.Surahs.SelectMany(s => library.Editions.Select(e =>
                    e.Id == library.DefaultEdition.Id ? $"/quran/{s.Number}" : $"/quran/{s.Number}?t={e.Id}")),
                request,
                site.Value));

        endpoints.MapGet("/sitemap-ayat.xml", (HttpRequest request, QuranLibrary library, IOptionsSnapshot<SiteOptions> site) =>
            UrlSet(
                Enumerable.Range(1, library.TotalAyah).Select(p => library.AtPosition(p).PagePath),
                request,
                site.Value));

        endpoints.MapGet("/robots.txt", (HttpRequest request, IOptionsSnapshot<SiteOptions> site) =>
            Results.Text($"User-agent: *\nAllow: /\n\nSitemap: {site.Value.AbsoluteUrl(request, "/sitemap.xml")}\n", "text/plain"));

        endpoints.MapGet("/site.webmanifest", () => Results.Json(
            new
            {
                name = "Daily Quran",
                short_name = "Daily Quran",
                description = "Read the Qur'an, one ayah at a time.",
                start_url = "/",
                display = "browser",
                background_color = "#FAF8F3",
                theme_color = "#1F4A3C",
                icons = new object[]
                {
                    new { src = "/img/icon-192.png", sizes = "192x192", type = "image/png" },
                    new { src = "/img/icon-512.png", sizes = "512x512", type = "image/png" },
                    new { src = "/img/icon.svg", sizes = "any", type = "image/svg+xml" },
                },
            },
            contentType: "application/manifest+json"));

        return endpoints;
    }

    private static IResult UrlSet(IEnumerable<string> paths, HttpRequest request, SiteOptions site) =>
        Xml(xml =>
        {
            xml.WriteStartElement("urlset", SitemapNamespace);
            foreach (string path in paths)
            {
                xml.WriteStartElement("url");
                xml.WriteElementString("loc", site.AbsoluteUrl(request, path));
                xml.WriteEndElement();
            }
            xml.WriteEndElement();
        });

    private static IResult Xml(Action<XmlWriter> write)
    {
        using var stream = new MemoryStream();
        using (var xml = XmlWriter.Create(stream, new XmlWriterSettings { Encoding = new UTF8Encoding(false) }))
        {
            xml.WriteStartDocument();
            write(xml);
            xml.WriteEndDocument();
        }
        return Results.Bytes(stream.ToArray(), "application/xml; charset=utf-8");
    }
}
