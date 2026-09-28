using System.Text;
using System.Xml;
using DailyQuran.Web.Quran;
using Microsoft.Extensions.Options;

namespace DailyQuran.Web.Site;

public static class SeoEndpoints
{
    private static readonly string[] Pages = ["/", "/features", "/quran", "/contact", "/privacy", "/sources"];

    public static IEndpointRouteBuilder MapSeoEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/sitemap.xml", (HttpRequest request, QuranLibrary library, IOptionsSnapshot<SiteOptions> site) =>
        {
            var builder = new StringBuilder();
            using (var xml = XmlWriter.Create(builder, new XmlWriterSettings { Indent = true, Encoding = Encoding.UTF8 }))
            {
                xml.WriteStartDocument();
                xml.WriteStartElement("urlset", "http://www.sitemaps.org/schemas/sitemap/0.9");
                IEnumerable<string> paths = Pages.Concat(library.Surahs.Select(s => $"/quran/{s.Number}"));
                foreach (string path in paths)
                {
                    xml.WriteStartElement("url");
                    xml.WriteElementString("loc", site.Value.AbsoluteUrl(request, path));
                    xml.WriteEndElement();
                }
                xml.WriteEndElement();
            }
            // StringBuilder output declares UTF-16; the response is UTF-8.
            string body = builder.ToString().Replace("encoding=\"utf-16\"", "encoding=\"utf-8\"");
            return Results.Text(body, "application/xml", Encoding.UTF8);
        });

        endpoints.MapGet("/robots.txt", (HttpRequest request, IOptionsSnapshot<SiteOptions> site) =>
            Results.Text($"User-agent: *\nAllow: /\nDisallow: /contact\n\nSitemap: {site.Value.AbsoluteUrl(request, "/sitemap.xml")}\n", "text/plain"));

        return endpoints;
    }
}
