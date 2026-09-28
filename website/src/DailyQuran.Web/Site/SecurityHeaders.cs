using System.Security.Cryptography;
using Microsoft.Extensions.Options;

namespace DailyQuran.Web.Site;

/// <summary>
/// A strict Content Security Policy — everything is served from this origin,
/// fonts included — and the usual hardening headers. Inline scripts, the one
/// that applies the reader's theme before the first paint and Google
/// Analytics' configuration, are allowed by a per-request nonce. With
/// analytics on (<see cref="SiteAnalytics"/>), Google's tag and measurement
/// hosts are allowed too, and nothing else is.
/// </summary>
public static class SecurityHeaders
{
    private const string NonceKey = "csp-nonce";

    public static string GetCspNonce(this HttpContext context) =>
        context.Items[NonceKey] as string ?? "";

    public static IApplicationBuilder UseSecurityHeaders(this IApplicationBuilder app) =>
        app.Use(async (context, next) =>
        {
            // Hex rather than Base64: nothing in it for Razor to HTML-encode.
            string nonce = Convert.ToHexString(RandomNumberGenerator.GetBytes(16));
            context.Items[NonceKey] = nonce;

            context.Response.OnStarting(() =>
            {
                IHeaderDictionary headers = context.Response.Headers;
                headers.XContentTypeOptions = "nosniff";
                headers["Referrer-Policy"] = "strict-origin-when-cross-origin";
                headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=(), interest-cohort=()";
                headers["Cross-Origin-Opener-Policy"] = "same-origin";

                if (context.Response.ContentType?.StartsWith("text/html", StringComparison.OrdinalIgnoreCase) == true)
                {
                    // The hosts Google documents for GA4 behind a CSP: the tag
                    // loads from Tag Manager, and measurements go to Analytics.
                    bool analytics = context.RequestServices
                        .GetRequiredService<IOptionsSnapshot<SiteOptions>>().Value.Analytics.IsEnabled;
                    string tagScripts = analytics ? " https://*.googletagmanager.com" : "";
                    string tagImages = analytics ? " https://*.google-analytics.com https://*.googletagmanager.com" : "";
                    string tagConnections = analytics
                        ? " https://*.google-analytics.com https://*.analytics.google.com https://*.googletagmanager.com"
                        : "";

                    headers.XFrameOptions = "DENY";
                    headers.ContentSecurityPolicy =
                        "default-src 'self'; " +
                        $"script-src 'self' 'nonce-{nonce}'{tagScripts}; " +
                        "style-src 'self'; " +
                        $"img-src 'self' data:{tagImages}; " +
                        "font-src 'self'; " +
                        $"connect-src 'self'{tagConnections}; " +
                        "form-action 'self'; " +
                        "frame-ancestors 'none'; " +
                        "base-uri 'self'; " +
                        "object-src 'none'";
                }
                return Task.CompletedTask;
            });

            await next(context);
        });
}
