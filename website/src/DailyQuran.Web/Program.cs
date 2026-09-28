using System.Threading.RateLimiting;
using DailyQuran.Web.Contact;
using DailyQuran.Web.Quran;
using DailyQuran.Web.Site;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.ResponseCompression;
using Microsoft.Extensions.Options;

WebApplicationBuilder builder = WebApplication.CreateBuilder(args);

builder.Services.AddRazorPages();
builder.Services.Configure<RouteOptions>(options => options.LowercaseUrls = true);

builder.Services.AddOptions<SiteOptions>().Bind(builder.Configuration.GetSection(SiteOptions.Section));
builder.Services.AddOptions<QuranOptions>().Bind(builder.Configuration.GetSection(QuranOptions.Section));
builder.Services.AddOptions<ContactOptions>().Bind(builder.Configuration.GetSection(ContactOptions.Section));

builder.Services.AddSingleton(TimeProvider.System);

// The whole Qur'an is read into memory once, at startup — a few tens of
// megabytes — so every page after that is served without touching the disk.
builder.Services.AddSingleton(services =>
{
    QuranOptions quran = services.GetRequiredService<IOptions<QuranOptions>>().Value;
    return QuranLibrary.Load(quran.ResolveDataPath(), quran.DefaultEdition);
});
builder.Services.AddSingleton<DailyAyah>();
builder.Services.AddSingleton(_ => SiteContent.Load(Path.Combine(AppContext.BaseDirectory, "content")));

// Contact form.
builder.Services.AddSingleton<ContactFormGuard>();
builder.Services.AddSingleton<IContactMailer>(services =>
    services.GetRequiredService<IOptions<ContactOptions>>().Value.Delivery == ContactDelivery.PickupDirectory
        ? ActivatorUtilities.CreateInstance<PickupDirectoryContactMailer>(services)
        : ActivatorUtilities.CreateInstance<SmtpContactMailer>(services));

// Keys protect the contact form's tokens. Kept in a folder when one is
// configured, so a restart or a second instance can still read them.
IDataProtectionBuilder dataProtection = builder.Services.AddDataProtection().SetApplicationName("DailyQuran.Web");
if (builder.Configuration["DataProtection:KeysPath"] is { Length: > 0 } keysPath)
{
    dataProtection.PersistKeysToFileSystem(new DirectoryInfo(keysPath));
}

// At most five messages per visitor in fifteen minutes. Nothing else is limited.
builder.Services.AddRateLimiter(options =>
{
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
        HttpMethods.IsPost(context.Request.Method) && context.Request.Path.StartsWithSegments("/contact")
            ? RateLimitPartition.GetFixedWindowLimiter(
                context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                _ => new FixedWindowRateLimiterOptions { PermitLimit = 5, Window = TimeSpan.FromMinutes(15) })
            : RateLimitPartition.GetNoLimiter("everything-else"));
    options.OnRejected = (context, _) =>
    {
        context.HttpContext.Response.StatusCode = StatusCodes.Status303SeeOther;
        context.HttpContext.Response.Headers.Location = "/contact?busy=true";
        return ValueTask.CompletedTask;
    };
});

builder.Services.AddResponseCompression(options =>
{
    options.EnableForHttps = true;
    options.Providers.Add<BrotliCompressionProvider>();
    options.Providers.Add<GzipCompressionProvider>();
    options.MimeTypes = ResponseCompressionDefaults.MimeTypes.Concat(["image/svg+xml"]);
});

builder.Services.AddHealthChecks();

WebApplication app = builder.Build();

// Read the Qur'an now rather than on the first visitor's request, and fail
// loudly here if the data is missing.
QuranLibrary library = app.Services.GetRequiredService<QuranLibrary>();
app.Logger.LogInformation(
    "Loaded {Ayat} ayat in {Editions} editions{Words}.",
    library.TotalAyah,
    library.Editions.Count,
    library.HasWordByWord ? ", with word-by-word glosses" : "");

if (!app.Services.GetRequiredService<IOptions<ContactOptions>>().Value.IsConfigured)
{
    app.Logger.LogWarning("The contact form is not configured: set Contact:Recipient and Contact:Smtp (see website/README.md). Visitors will be told messages cannot be sent.");
}

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/error");
    app.UseHsts();
}

app.UseStatusCodePagesWithReExecute("/status/{0}");
app.UseSecurityHeaders();

// Compress everything except the contact form, whose pages carry a secret
// token beside text the visitor typed — the combination BREACH exploits.
app.UseWhen(
    context => !context.Request.Path.StartsWithSegments("/contact"),
    branch => branch.UseResponseCompression());

app.UseRateLimiter();

app.MapStaticAssets();
app.MapRazorPages().WithStaticAssets();
app.MapSeoEndpoints();
app.MapHealthChecks("/healthz");

app.Run();
