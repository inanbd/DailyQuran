using System.Net;
using System.Text.RegularExpressions;

namespace DailyQuran.Web.Tests;

public sealed class PageTests(SiteFactory site) : IClassFixture<SiteFactory>
{
    private readonly HttpClient _client = site.CreateClient();

    [Theory]
    [InlineData("/", "Daily Quran")]
    [InlineData("/features", "Seven editions, six languages")]
    [InlineData("/quran", "Read the Qur’an")]
    [InlineData("/quran/1", "Al-Fatihah")]
    [InlineData("/quran/2/255", "Al-Baqarah 2:255")]
    [InlineData("/contact", "Send message")]
    [InlineData("/privacy", "Daily Quran does not collect, store or share any personal information")]
    [InlineData("/sources", "Creative Commons Attribution-ShareAlike 4.0")]
    public async Task Every_page_opens(string path, string expected)
    {
        HttpResponseMessage response = await _client.GetAsync(path);
        string html = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains(expected, WebUtility.HtmlDecode(html));
    }

    [Theory]
    [InlineData("/quran/0")]
    [InlineData("/quran/115")]
    [InlineData("/quran/1/8")]
    [InlineData("/quran/2/287")]
    [InlineData("/no-such-page")]
    public async Task An_address_that_is_not_there_is_a_gentle_404(string path)
    {
        HttpResponseMessage response = await _client.GetAsync(path);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Contains("This page could not be found", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task A_surah_shows_every_ayah_under_the_basmala()
    {
        string html = await _client.GetStringAsync("/quran/2");

        Assert.Equal(286, Html.Count(html, "class=\"ayah\" id=\"a"));
        Assert.Contains("class=\"basmala\"", html);
        Assert.Contains("id=\"a255\"", html);
    }

    [Fact]
    public async Task At_Tawbah_has_no_basmala_heading()
    {
        Assert.DoesNotContain("class=\"basmala\"", await _client.GetStringAsync("/quran/9"));
    }

    [Fact]
    public async Task A_chosen_translation_is_laid_out_in_its_own_language_and_remembered()
    {
        HttpResponseMessage response = await _client.GetAsync("/quran/1?t=maududi");
        string html = await response.Content.ReadAsStringAsync();

        Assert.Contains("class=\"translation\" lang=\"ur-PK\" dir=\"rtl\"", html);
        Assert.Contains(response.Headers.GetValues("Set-Cookie"), c => c.StartsWith("dq_reader=maududi", StringComparison.Ordinal));
    }

    [Fact]
    public async Task Word_by_word_replaces_the_running_Arabic_and_keeps_the_translation()
    {
        string plain = await _client.GetStringAsync("/quran/1?t=saheeh_international&wbw=0");
        string words = await _client.GetStringAsync("/quran/1?t=saheeh_international&wbw=1");

        Assert.Equal(7, Html.Count(plain, "class=\"arabic\""));
        Assert.DoesNotContain("class=\"wbw\"", plain);
        Assert.Equal(7, Html.Count(words, "class=\"wbw\""));
        Assert.DoesNotContain("class=\"arabic\"", words);
        Assert.Equal(7, Html.Count(words, "class=\"translation\""));
    }

    [Fact]
    public async Task The_Arabic_alone_shows_no_translation()
    {
        string html = await _client.GetStringAsync("/quran/112?t=arabic_uthmani&wbw=0");

        Assert.Equal(4, Html.Count(html, "class=\"arabic\""));
        Assert.DoesNotContain("class=\"translation\"", html);
    }

    [Fact]
    public async Task Pages_carry_a_strict_content_security_policy_whose_nonce_matches_the_inline_script()
    {
        HttpResponseMessage response = await _client.GetAsync("/");
        string html = await response.Content.ReadAsStringAsync();
        string policy = response.Headers.GetValues("Content-Security-Policy").Single();

        string nonce = Regex.Match(policy, "'nonce-([^']+)'").Groups[1].Value;
        Assert.NotEmpty(nonce);
        Assert.Contains($"<script nonce=\"{nonce}\">", html);
        Assert.Contains("default-src 'self'", policy);
        Assert.Contains("frame-ancestors 'none'", policy);
        Assert.Equal("nosniff", response.Headers.GetValues("X-Content-Type-Options").Single());
    }

    [Fact]
    public async Task The_store_badges_follow_the_settings()
    {
        // appsettings.json: Google Play in internal testing, the App Store not yet.
        string html = WebUtility.HtmlDecode(await _client.GetStringAsync("/"));

        Assert.Contains("href=\"https://play.google.com/apps/internaltest/4701262937540230372\"", html);
        Assert.Contains("store-badge is-soon", html);
        Assert.Contains("Download on the App Store — coming soon", html);
    }

    [Fact]
    public async Task While_in_testing_the_badges_say_how_to_get_access()
    {
        string html = WebUtility.HtmlDecode(await _client.GetStringAsync("/"));

        Assert.Contains("The Android app is in internal testing on Google Play.", html);
        Assert.Contains("<a href=\"/contact?topic=access\">Contact the developer</a> to get access.", html);
        // Above the badges, in the hero and in the download section alike.
        Assert.Equal(2, Html.Count(html, "class=\"store-note\""));
        Assert.True(html.IndexOf("class=\"store-note\"", StringComparison.Ordinal) < html.IndexOf("google-play.svg", StringComparison.Ordinal));
    }

    [Fact]
    public async Task The_sitemap_lists_every_page_surah_and_ayah()
    {
        string index = await _client.GetStringAsync("/sitemap.xml");
        Assert.StartsWith("<?xml version=\"1.0\" encoding=\"utf-8\"?>", index);
        Assert.Contains("<sitemapindex", index);
        Assert.Equal(3, Regex.Matches(index, "<sitemap>").Count);

        string pages = await _client.GetStringAsync("/sitemap-pages.xml");
        string surahs = await _client.GetStringAsync("/sitemap-surahs.xml");
        string ayat = await _client.GetStringAsync("/sitemap-ayat.xml");

        Assert.Equal(6, Regex.Matches(pages, "<loc>").Count);
        // Each surah once in every edition: 114 x 7.
        Assert.Equal(798, Regex.Matches(surahs, "<loc>").Count);
        Assert.Equal(114, Regex.Matches(surahs, @"/quran/\d+</loc>").Count);
        Assert.Contains("/quran/36?t=maududi</loc>", surahs);
        Assert.Equal(6236, Regex.Matches(ayat, "<loc>").Count);
        Assert.Contains("/quran/2/255</loc>", ayat);
        Assert.Contains("/quran/114/6</loc>", ayat);
    }

    [Fact]
    public async Task The_home_page_offers_an_ayah_for_today_in_the_readers_translation()
    {
        string html = await _client.GetStringAsync("/?t=hamidullah");
        Assert.Contains("class=\"daily-translation\" lang=\"fr-FR\"", html);
    }
}

public sealed class LiveOnGooglePlayTests(SiteLiveFactory site) : IClassFixture<SiteLiveFactory>
{
    private readonly HttpClient _client = site.CreateClient();

    [Fact]
    public async Task Once_live_the_badge_goes_to_the_listing_and_the_note_is_gone()
    {
        string html = WebUtility.HtmlDecode(await _client.GetStringAsync("/"));

        Assert.Contains("href=\"https://play.google.com/store/apps/details?id=com.i9tech.qurandaily\"", html);
        Assert.DoesNotContain("store-note", html);
        Assert.DoesNotContain("internal testing", html);
    }

    [Fact]
    public async Task Once_live_the_contact_form_no_longer_offers_access()
    {
        string html = WebUtility.HtmlDecode(await _client.GetStringAsync("/contact?topic=access"));

        Assert.DoesNotContain("value=\"access\"", html);
        Assert.DoesNotContain("Want the Android app?", html);
        Assert.Contains("<option value=\"question\" selected=\"selected\">", html);
    }
}

public sealed class StoreLinkTests(SiteWithAppStoreFactory site) : IClassFixture<SiteWithAppStoreFactory>
{
    [Fact]
    public async Task A_configured_App_Store_link_is_a_link_and_an_empty_Play_link_is_coming_soon()
    {
        string html = WebUtility.HtmlDecode(await site.CreateClient().GetStringAsync("/"));

        Assert.Contains("href=\"https://apps.apple.com/app/id000000000\"", html);
        Assert.Contains("Get it on Google Play — coming soon", html);
    }
}
