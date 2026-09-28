using DailyQuran.Web.Contact;
using DailyQuran.Web.Quran;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using System.Collections.Concurrent;
using System.Text.RegularExpressions;

namespace DailyQuran.Web.Tests;

/// <summary>A clock the tests move by hand.</summary>
public sealed class ManualClock(DateTimeOffset start) : TimeProvider
{
    public DateTimeOffset Now { get; set; } = start;

    public override DateTimeOffset GetUtcNow() => Now;

    public void Advance(TimeSpan by) => Now += by;
}

/// <summary>Keeps what would have been emailed.</summary>
public sealed class RecordingMailer : IContactMailer
{
    public ConcurrentQueue<ContactMessage> Sent { get; } = new();

    public bool Fail { get; set; }

    public Task SendAsync(ContactMessage message, CancellationToken cancellationToken)
    {
        if (Fail)
        {
            throw new InvalidOperationException("The mail server is down.");
        }
        Sent.Enqueue(message);
        return Task.CompletedTask;
    }
}

/// <summary>The whole site, in memory, with a hand-moved clock and a mailer that records instead of sending.</summary>
public class SiteFactory : WebApplicationFactory<Program>
{
    public ManualClock Clock { get; } = new(DateTimeOffset.UtcNow);

    public RecordingMailer Mailer { get; } = new();

    protected virtual IDictionary<string, string?> Settings => new Dictionary<string, string?>
    {
        ["Contact:Recipient"] = "owner@example.com",
        ["Contact:Delivery"] = "PickupDirectory",
    };

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        foreach ((string key, string? value) in Settings)
        {
            builder.UseSetting(key, value);
        }
        builder.ConfigureTestServices(services =>
        {
            services.AddSingleton<TimeProvider>(Clock);
            services.AddSingleton<IContactMailer>(Mailer);
        });
    }
}

public sealed class SiteWithAppStoreFactory : SiteFactory
{
    protected override IDictionary<string, string?> Settings => new Dictionary<string, string?>(base.Settings)
    {
        ["Site:Stores:AppStore"] = "https://apps.apple.com/app/id000000000",
        ["Site:Stores:GooglePlay"] = "",
    };
}

/// <summary>The site with Google Analytics turned off, or given something that is not a measurement ID.</summary>
public class SiteWithoutAnalyticsFactory : SiteFactory
{
    protected virtual string MeasurementId => "";

    protected override IDictionary<string, string?> Settings => new Dictionary<string, string?>(base.Settings)
    {
        ["Site:Analytics:GoogleMeasurementId"] = MeasurementId,
    };
}

public sealed class SiteWithBadAnalyticsIdFactory : SiteWithoutAnalyticsFactory
{
    protected override string MeasurementId => "G-123'); alert('x";
}

/// <summary>The site once the app is public on Google Play.</summary>
public sealed class SiteLiveFactory : SiteFactory
{
    protected override IDictionary<string, string?> Settings => new Dictionary<string, string?>(base.Settings)
    {
        ["Site:Stores:GooglePlay"] = "https://play.google.com/store/apps/details?id=com.i9tech.qurandaily",
        ["Site:Stores:GooglePlayInternalTesting"] = "false",
    };
}

public sealed class SiteWithoutMailFactory : SiteFactory
{
    protected override IDictionary<string, string?> Settings => new Dictionary<string, string?>
    {
        ["Contact:Recipient"] = "",
    };
}

/// <summary>The data the app ships, loaded once for every test that reads it.</summary>
public sealed class LibraryFixture
{
    public QuranLibrary Library { get; } =
        QuranLibrary.Load(Path.Combine(AppContext.BaseDirectory, "data"), "saheeh_international");
}

public static partial class Html
{
    public static string HiddenValue(string html, string name)
    {
        Match match = Regex.Match(html, $"<input[^>]*name=\"{Regex.Escape(name)}\"[^>]*value=\"([^\"]*)\"");
        if (!match.Success)
        {
            match = Regex.Match(html, $"<input[^>]*value=\"([^\"]*)\"[^>]*name=\"{Regex.Escape(name)}\"");
        }
        Assert.True(match.Success, $"No hidden field named {name}.");
        return System.Net.WebUtility.HtmlDecode(match.Groups[1].Value);
    }

    public static int Count(string html, string fragment) => Regex.Matches(html, Regex.Escape(fragment)).Count;

    /// <summary>The nonce a response's Content Security Policy allows scripts by.</summary>
    public static string HiddenNonce(HttpResponseMessage response) =>
        Regex.Match(response.Headers.GetValues("Content-Security-Policy").Single(), "'nonce-([^']+)'").Groups[1].Value;
}
