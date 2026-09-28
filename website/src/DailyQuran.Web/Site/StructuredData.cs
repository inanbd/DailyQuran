using System.Text.Json;
using DailyQuran.Web.Quran;
using Microsoft.AspNetCore.Html;

namespace DailyQuran.Web.Site;

/// <summary>
/// schema.org descriptions of the site, the app and where each page sits, as
/// JSON-LD. Search engines read them for richer results — breadcrumbs under a
/// surah's listing, the app's details beside its name.
/// </summary>
public static class StructuredData
{
    // The default encoder escapes <, > and &, so nothing in the data can close
    // the script element it is written into.
    private static readonly JsonSerializerOptions Json = new() { WriteIndented = false };

    public static HtmlString Script(object data, string nonce) =>
        new($"<script type=\"application/ld+json\" nonce=\"{nonce}\">{JsonSerializer.Serialize(data, Json)}</script>");

    /// <summary>The site and the publisher behind it, on every page.</summary>
    public static object Site(SiteOptions site, HttpRequest request)
    {
        string home = site.AbsoluteUrl(request, "/");
        var publisher = new Dictionary<string, object>
        {
            ["@type"] = "Organization",
            ["@id"] = home + "#publisher",
            ["name"] = site.Publisher,
            ["url"] = home,
            ["logo"] = site.AbsoluteUrl(request, "/img/icon-512.png"),
        };
        if (site.SourceCodeUrl.Length > 0)
        {
            publisher["sameAs"] = new[] { site.SourceCodeUrl };
        }

        return new Dictionary<string, object>
        {
            ["@context"] = "https://schema.org",
            ["@graph"] = new object[]
            {
                publisher,
                new Dictionary<string, object>
                {
                    ["@type"] = "WebSite",
                    ["@id"] = home + "#website",
                    ["name"] = "Daily Quran",
                    ["url"] = home,
                    ["inLanguage"] = "en",
                    ["publisher"] = new Dictionary<string, object> { ["@id"] = home + "#publisher" },
                },
            },
        };
    }

    /// <summary>The app itself, for the pages that are about it.</summary>
    public static object App(SiteOptions site, HttpRequest request)
    {
        var app = new Dictionary<string, object>
        {
            ["@context"] = "https://schema.org",
            ["@type"] = "MobileApplication",
            ["name"] = "Daily Quran",
            ["description"] = "A quiet Qur'an reading app: one ayah at a time with its translation, gentle reminders, and a plan to finish the whole Qur'an by a date you choose.",
            ["operatingSystem"] = site.Stores.AppStore.Length > 0 ? "Android, iOS" : "Android",
            ["applicationCategory"] = "BookApplication",
            ["url"] = site.AbsoluteUrl(request, "/"),
            ["image"] = site.AbsoluteUrl(request, "/img/icon-512.png"),
            ["screenshot"] = PhoneShot.All.Select(s => site.AbsoluteUrl(request, $"/img/screens/{s.File}")).ToArray(),
            ["inLanguage"] = new[] { "en", "ur", "bn", "fr", "es", "ru", "ar" },
            ["publisher"] = new Dictionary<string, object> { ["@id"] = site.AbsoluteUrl(request, "/") + "#publisher" },
        };
        string[] downloads = new[] { site.Stores.GooglePlay, site.Stores.AppStore }.Where(u => u.Length > 0).ToArray();
        if (downloads.Length > 0)
        {
            app["downloadUrl"] = downloads;
        }
        return app;
    }

    /// <summary>Home › … › this page, as a trail search results can show.</summary>
    public static object Breadcrumbs(SiteOptions site, HttpRequest request, params (string Name, string Path)[] trail) =>
        new Dictionary<string, object>
        {
            ["@context"] = "https://schema.org",
            ["@type"] = "BreadcrumbList",
            ["itemListElement"] = trail
                .Select((step, i) => new Dictionary<string, object>
                {
                    ["@type"] = "ListItem",
                    ["position"] = i + 1,
                    ["name"] = step.Name,
                    ["item"] = site.AbsoluteUrl(request, step.Path),
                })
                .ToArray(),
        };

    /// <summary>The trail to a surah: Home › The Qur'an › Al-Baqarah.</summary>
    public static (string Name, string Path)[] SurahTrail(Surah surah) =>
    [
        ("Daily Quran", "/"),
        ("The Qur'an", "/quran"),
        ($"Surah {surah.NameTransliterated}", $"/quran/{surah.Number}"),
    ];
}
