using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;
using DailyQuran.Web.Quran;
using DailyQuran.Web.Site;

namespace DailyQuran.Web.Tests;

public sealed class AyahPageTests(SiteFactory site) : IClassFixture<SiteFactory>
{
    private readonly HttpClient _client = site.CreateClient();

    private async Task<string> Page(string path) => WebUtility.HtmlDecode(await _client.GetStringAsync(path));

    [Fact]
    public async Task An_ayah_has_a_page_of_its_own_with_every_translation()
    {
        string html = await Page("/quran/2/255");

        Assert.Contains("<title>Al-Baqarah 2:255 — Arabic, word by word & translations · Daily Quran</title>", html);
        Assert.Contains("<link rel=\"canonical\" href=\"http://localhost/quran/2/255\">", html);
        Assert.Contains("class=\"ayah-sheet-arabic\" lang=\"ar\" dir=\"rtl\"", html);
        foreach (string language in new[] { "en-US", "ur-PK", "bn-BD", "fr-FR", "es-ES", "ru-RU" })
        {
            Assert.Contains($"class=\"translation\" lang=\"{language}\"", html);
        }
        Assert.Contains("class=\"wbw wbw-sheet\"", html);
        Assert.Contains("href=\"/quran/2#a255\"", html);
    }

    [Fact]
    public async Task Searchers_see_English_first_and_readers_see_their_own()
    {
        string anyone = await Page("/quran/1/1");
        string urduReader = await Page("/quran/1/1?t=maududi");

        Assert.Equal("en-US", FirstTranslationLanguage(anyone));
        Assert.Equal("ur-PK", FirstTranslationLanguage(urduReader));
        // Either way, the address search engines keep is the ayah's alone.
        Assert.Contains("<link rel=\"canonical\" href=\"http://localhost/quran/1/1\">", urduReader);
    }

    [Fact]
    public async Task Previous_and_next_cross_from_one_surah_into_the_next()
    {
        string end = await Page("/quran/2/286");
        Assert.Contains("href=\"/quran/2/285\"", end);
        Assert.Contains("href=\"/quran/3/1\"", end);

        string first = await Page("/quran/1/1");
        Assert.DoesNotContain("Previous ayah", first);
        Assert.Contains("href=\"/quran/1/2\"", first);

        string last = await Page("/quran/114/6");
        Assert.DoesNotContain("Next ayah", last);
    }

    [Fact]
    public async Task An_ayah_page_describes_its_place_for_search_results()
    {
        string html = await Page("/quran/36/1");
        JsonElement crumbs = JsonLd(html).Single(d => d.TryGetProperty("@type", out JsonElement type) && type.GetString() == "BreadcrumbList");
        string[] names = crumbs.GetProperty("itemListElement").EnumerateArray()
            .Select(i => i.GetProperty("name").GetString()!).ToArray();

        Assert.Equal(new[] { "Daily Quran", "The Qur'an", "Surah Ya-Sin", "Ayah 1" }, names);
    }

    private static string FirstTranslationLanguage(string html) =>
        Regex.Match(html, "class=\"translation\" lang=\"([^\"]+)\"").Groups[1].Value;

    internal static IEnumerable<JsonElement> JsonLd(string html) =>
        Regex.Matches(html, "<script type=\"application/ld\\+json\"[^>]*>(.*?)</script>", RegexOptions.Singleline)
            .Select(m => JsonDocument.Parse(m.Groups[1].Value).RootElement);
}

public sealed class SearchEngineTests(SiteFactory site) : IClassFixture<SiteFactory>
{
    private readonly HttpClient _client = site.CreateClient();

    private async Task<string> Page(string path) => WebUtility.HtmlDecode(await (await _client.GetAsync(path)).Content.ReadAsStringAsync());

    [Fact]
    public async Task Each_translation_of_a_surah_names_the_others_by_language()
    {
        string html = await Page("/quran/36?t=kuliev");

        Assert.Contains("<link rel=\"canonical\" href=\"http://localhost/quran/36?t=kuliev\">", html);
        Assert.Contains("<title>Surah Ya-Sin (Ya Sin) — Russian translation, Kuliev · Daily Quran</title>", html);
        foreach ((string tag, string path) in new[]
        {
            ("en", "/quran/36"), ("ur", "/quran/36?t=maududi"), ("bn", "/quran/36?t=muhiuddin_khan"),
            ("fr", "/quran/36?t=hamidullah"), ("es", "/quran/36?t=garcia"), ("ru", "/quran/36?t=kuliev"),
            ("ar", "/quran/36?t=arabic_uthmani"), ("x-default", "/quran/36"),
        })
        {
            Assert.Contains($"<link rel=\"alternate\" hreflang=\"{tag}\" href=\"http://localhost{path}\">", html);
        }
    }

    [Fact]
    public async Task Word_by_word_is_a_view_of_the_same_page_not_a_page_of_its_own()
    {
        string html = await Page("/quran/36?t=kuliev&wbw=1");
        Assert.Contains("<link rel=\"canonical\" href=\"http://localhost/quran/36?t=kuliev\">", html);
    }

    [Fact]
    public async Task A_surah_page_says_where_the_surah_sits()
    {
        // As a browser shows it: runs of whitespace are one space.
        string html = Regex.Replace(await Page("/quran/2"), @"\s+", " ");
        Assert.Contains("is surah 2 of the 114 in the Qur’an, revealed in Medina, with 286 ayat", html);
        Assert.Contains("ayat 8 to 293 of 6,236", html);
    }

    [Theory]
    [InlineData("/no-such-page")]
    [InlineData("/quran/2/999")]
    [InlineData("/contact?sent=true")]
    public async Task Pages_nobody_should_land_on_from_a_search_ask_not_to_be_indexed(string path)
    {
        string html = await Page(path);
        Assert.Contains("<meta name=\"robots\" content=\"noindex\">", html);
        Assert.DoesNotContain("rel=\"canonical\"", html);
    }

    [Fact]
    public async Task Real_pages_invite_indexing_and_large_previews()
    {
        string html = await Page("/features");
        Assert.Contains("<meta name=\"robots\" content=\"index, follow, max-image-preview:large\">", html);
        Assert.Contains("<meta name=\"twitter:title\" content=\"Features\">", html);
    }

    [Fact]
    public async Task Robots_let_everything_be_crawled_and_point_to_the_sitemap()
    {
        string robots = await _client.GetStringAsync("/robots.txt");
        Assert.DoesNotContain("Disallow", robots);
        Assert.Contains("Sitemap: http://localhost/sitemap.xml", robots);
    }

    [Fact]
    public async Task The_home_page_describes_the_site_the_publisher_and_the_app()
    {
        string html = await Page("/");
        JsonElement[] data = AyahPageTests.JsonLd(html).ToArray();

        JsonElement graph = data.Single(d => d.TryGetProperty("@graph", out _)).GetProperty("@graph");
        Assert.Contains(graph.EnumerateArray(), n => n.GetProperty("@type").GetString() == "WebSite");
        Assert.Contains(graph.EnumerateArray(), n => n.GetProperty("@type").GetString() == "Organization" && n.GetProperty("name").GetString() == "i9Tech");

        JsonElement app = data.Single(d => d.TryGetProperty("@type", out JsonElement t) && t.GetString() == "MobileApplication");
        Assert.Equal("Android", app.GetProperty("operatingSystem").GetString());
        Assert.Equal("https://play.google.com/apps/internaltest/4701262937540230372", app.GetProperty("downloadUrl")[0].GetString());
        Assert.Equal(5, app.GetProperty("screenshot").GetArrayLength());
    }

    [Fact]
    public async Task The_manifest_names_the_app_and_its_icons()
    {
        HttpResponseMessage response = await _client.GetAsync("/site.webmanifest");
        JsonElement manifest = JsonDocument.Parse(await response.Content.ReadAsStringAsync()).RootElement;

        Assert.Equal("application/manifest+json", response.Content.Headers.ContentType!.MediaType);
        Assert.Equal("Daily Quran", manifest.GetProperty("name").GetString());
        foreach (JsonElement icon in manifest.GetProperty("icons").EnumerateArray())
        {
            HttpResponseMessage image = await _client.GetAsync(icon.GetProperty("src").GetString());
            Assert.Equal(HttpStatusCode.OK, image.StatusCode);
        }
    }

    [Fact]
    public async Task The_surah_index_links_the_surahs_people_look_for()
    {
        string html = await Page("/quran");
        Assert.Contains("<a class=\"chip\" href=\"/quran/36\">Ya-Sin</a>", html);
        Assert.Contains("<a class=\"chip\" href=\"/quran/2/255\">Ayat al-Kursi</a>", html);
    }
}

public sealed class VerifiedSiteFactory : SiteFactory
{
    protected override IDictionary<string, string?> Settings => new Dictionary<string, string?>(base.Settings)
    {
        ["Site:Verification:Google"] = "google-code-123",
        ["Site:Verification:Bing"] = "bing-code-456",
        ["Site:BaseUrl"] = "https://dailyquran.example/",
    };
}

public sealed class VerificationTests(VerifiedSiteFactory site) : IClassFixture<VerifiedSiteFactory>
{
    [Fact]
    public async Task Search_console_codes_and_the_public_address_come_from_settings()
    {
        string html = await site.CreateClient().GetStringAsync("/quran/1");

        Assert.Contains("<meta name=\"google-site-verification\" content=\"google-code-123\">", html);
        Assert.Contains("<meta name=\"msvalidate.01\" content=\"bing-code-456\">", html);
        Assert.Contains("<link rel=\"canonical\" href=\"https://dailyquran.example/quran/1\">", html);
    }
}

public sealed class ReleaseNotesTests
{
    [Fact]
    public void Whats_new_skips_work_not_yet_released()
    {
        string folder = Directory.CreateTempSubdirectory().FullName;
        File.WriteAllText(Path.Combine(folder, "CHANGELOG.md"), "# Changelog\n\n## Unreleased\n\n- Not out yet.\n\n## 1.3.0\n\n- Already out.\n\n## 1.2.0\n\n- Older.\n");

        ReleaseNotes notes = SiteContent.Load(folder).LatestRelease!;

        Assert.Equal("1.3.0", notes.Version);
        Assert.Contains("Already out.", notes.Html.Value);
        Assert.DoesNotContain("Older.", notes.Html.Value);
    }
}

public sealed class ReadingPositionTests(LibraryFixture fixture) : IClassFixture<LibraryFixture>
{
    private readonly QuranLibrary _library = fixture.Library;

    [Theory]
    [InlineData(1, 1, 1)]
    [InlineData(262, 2, 255)]
    [InlineData(294, 3, 1)]
    [InlineData(6236, 114, 6)]
    public void A_reading_position_finds_its_ayah(int position, int surah, int ayah)
    {
        AyahRef found = _library.AtPosition(position);
        Assert.Equal((surah, ayah), (found.Surah.Number, found.Number));
    }

    [Fact]
    public void Every_position_round_trips()
    {
        for (int position = 1; position <= _library.TotalAyah; position++)
        {
            AyahRef found = _library.AtPosition(position);
            Assert.Equal(position, _library.ReadingPosition(found.Surah.Number, found.Number));
        }
    }

    [Fact]
    public void An_ayah_in_every_translation_leads_with_the_one_asked_for()
    {
        IReadOnlyList<AyahTranslation> all = _library.TranslationsOf(2, 255, _library.FindEdition("hamidullah"));

        Assert.Equal(6, all.Count);
        Assert.Equal("hamidullah", all[0].Edition.Id);
        Assert.DoesNotContain(all, t => !t.Edition.HasTranslation);
    }
}
