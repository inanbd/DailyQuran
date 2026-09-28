namespace DailyQuran.Web.Site;

/// <summary>The <c>Site</c> section of appsettings.json.</summary>
public sealed class SiteOptions
{
    public const string Section = "Site";

    /// <summary>
    /// The public address of the site, e.g. <c>https://dailyquran.app</c>, used
    /// for canonical links, the sitemap and link previews. Left empty, the
    /// address each request arrived on is used.
    /// </summary>
    public string BaseUrl { get; set; } = "";

    /// <summary>Who publishes the app, for the footer.</summary>
    public string Publisher { get; set; } = "i9Tech";

    public StoreLinks Stores { get; set; } = new();

    /// <summary>Where the app's source and issue tracker live. Empty hides the links.</summary>
    public string SourceCodeUrl { get; set; } = "";

    public SiteVerification Verification { get; set; } = new();

    public SiteAnalytics Analytics { get; set; } = new();

    public string AbsoluteUrl(HttpRequest request, string path)
    {
        string origin = BaseUrl.Length > 0
            ? BaseUrl.TrimEnd('/')
            : $"{request.Scheme}://{request.Host}{request.PathBase}";
        return origin + (path.StartsWith('/') ? path : "/" + path);
    }
}

/// <summary>
/// Download links for the app. A link left empty shows its badge as
/// "Coming soon" rather than as a link that goes nowhere.
/// </summary>
public sealed class StoreLinks
{
    public string GooglePlay { get; set; } = "";

    /// <summary>
    /// While the app is in internal testing on Google Play, only testers the
    /// developer has added can install it. On, a note above the Google Play
    /// badge asks visitors to get in touch for access, and the contact form
    /// offers that as a topic. Turn it off when the app goes public.
    /// </summary>
    public bool GooglePlayInternalTesting { get; set; }

    public string AppStore { get; set; } = "";

    /// <summary>A direct APK download, offered in small print beneath the badges.</summary>
    public string Apk { get; set; } = "";
}

/// <summary>
/// The codes Google Search Console and Bing Webmaster Tools give to prove the
/// site is yours: the <c>content</c> of the meta tag each one asks you to add.
/// Empty leaves the tag out.
/// </summary>
public sealed class SiteVerification
{
    public string Google { get; set; } = "";

    public string Bing { get; set; } = "";
}

/// <summary>
/// Google Analytics for the website — the app has none. Off while
/// <see cref="GoogleMeasurementId"/> is empty.
/// </summary>
public sealed partial class SiteAnalytics
{
    /// <summary>The GA4 measurement ID, e.g. <c>G-T4PP77VBM8</c>.</summary>
    public string GoogleMeasurementId { get; set; } = "";

    /// <summary>
    /// The measurement ID, when it is one. It is written into a script and a
    /// URL, so anything else — a typo, a stray quote — turns analytics off
    /// rather than going on the page.
    /// </summary>
    public string? MeasurementId =>
        MeasurementIdShape().IsMatch(GoogleMeasurementId.Trim()) ? GoogleMeasurementId.Trim() : null;

    public bool IsEnabled => MeasurementId is not null;

    [System.Text.RegularExpressions.GeneratedRegex("^G-[A-Z0-9]{4,20}$")]
    private static partial System.Text.RegularExpressions.Regex MeasurementIdShape();
}

/// <summary>The <c>Quran</c> section of appsettings.json.</summary>
public sealed class QuranOptions
{
    public const string Section = "Quran";

    /// <summary>
    /// The folder holding catalog.json, surahs.json, word_by_word.json and
    /// editions/. Relative paths are resolved against the app's own folder,
    /// where the build copies the repository's <c>assets/data</c>.
    /// </summary>
    public string DataPath { get; set; } = "data";

    /// <summary>The edition a first-time reader sees.</summary>
    public string DefaultEdition { get; set; } = "saheeh_international";

    public string ResolveDataPath() =>
        Path.IsPathRooted(DataPath) ? DataPath : Path.Combine(AppContext.BaseDirectory, DataPath);
}
