using System.Net;

namespace DailyQuran.Web.Tests;

public sealed class AnalyticsTests(SiteFactory site) : IClassFixture<SiteFactory>
{
    private readonly HttpClient _client = site.CreateClient();

    [Theory]
    [InlineData("/")]
    [InlineData("/quran/2")]
    [InlineData("/quran/2/255")]
    [InlineData("/contact")]
    public async Task Every_page_carries_the_google_tag(string path)
    {
        HttpResponseMessage response = await _client.GetAsync(path);
        string html = await response.Content.ReadAsStringAsync();
        string nonce = Html.HiddenNonce(response);

        Assert.Contains($"<script async src=\"https://www.googletagmanager.com/gtag/js?id=G-T4PP77VBM8\" nonce=\"{nonce}\"></script>", html);
        Assert.Contains("gtag('config', 'G-T4PP77VBM8');", html);
        // First in the head, as Google asks, so visits are counted however
        // soon someone leaves.
        Assert.True(html.IndexOf("googletagmanager", StringComparison.Ordinal) < html.IndexOf("<title>", StringComparison.Ordinal));
    }

    [Fact]
    public async Task The_security_policy_lets_google_analytics_through_and_nothing_else()
    {
        HttpResponseMessage response = await _client.GetAsync("/");
        string policy = response.Headers.GetValues("Content-Security-Policy").Single();

        Assert.Contains("script-src 'self' 'nonce-", policy);
        Assert.Contains(" https://*.googletagmanager.com;", policy);
        Assert.Contains("img-src 'self' data: https://*.google-analytics.com https://*.googletagmanager.com;", policy);
        Assert.Contains("connect-src 'self' https://*.google-analytics.com https://*.analytics.google.com https://*.googletagmanager.com;", policy);
        Assert.Contains("style-src 'self';", policy);
        Assert.Contains("font-src 'self';", policy);
    }

    [Fact]
    public async Task The_privacy_page_says_so()
    {
        string html = WebUtility.HtmlDecode(await _client.GetStringAsync("/privacy"));

        Assert.Contains("counts its visits with Google Analytics", html);
        Assert.Contains("<code>_ga</code>", html);
        Assert.Contains("https://tools.google.com/dlpage/gaoptout", html);
        Assert.DoesNotContain("no analytics — in the app or on this website", html);
    }
}

public sealed class NoAnalyticsTests(SiteWithoutAnalyticsFactory site) : IClassFixture<SiteWithoutAnalyticsFactory>
{
    [Fact]
    public async Task Without_an_id_there_is_no_tag_no_opening_in_the_policy_and_no_claim_otherwise()
    {
        HttpClient client = site.CreateClient();
        HttpResponseMessage response = await client.GetAsync("/");
        string html = await response.Content.ReadAsStringAsync();
        string privacy = WebUtility.HtmlDecode(await client.GetStringAsync("/privacy"));

        Assert.DoesNotContain("googletagmanager", html);
        Assert.DoesNotContain("google", response.Headers.GetValues("Content-Security-Policy").Single());
        Assert.Contains("no analytics — in the app or on this website", privacy);
        Assert.DoesNotContain("_ga", privacy);
    }
}

public sealed class BadAnalyticsIdTests(SiteWithBadAnalyticsIdFactory site) : IClassFixture<SiteWithBadAnalyticsIdFactory>
{
    [Fact]
    public async Task Something_that_is_not_a_measurement_id_never_reaches_the_page()
    {
        string html = await site.CreateClient().GetStringAsync("/");

        Assert.DoesNotContain("googletagmanager", html);
        Assert.DoesNotContain("alert", html);
    }
}
