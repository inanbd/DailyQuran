using System.Security.Cryptography;

namespace DailyQuran.Web.Site;

/// <summary>
/// A strict Content Security Policy — everything is served from this origin,
/// fonts included, so the site makes no third-party requests at all — and the
/// usual hardening headers. The one inline script, which applies the reader's
/// theme before the first paint, is allowed by a per-request nonce.
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
                    headers.XFrameOptions = "DENY";
                    headers.ContentSecurityPolicy =
                        "default-src 'self'; " +
                        $"script-src 'self' 'nonce-{nonce}'; " +
                        "style-src 'self'; " +
                        "img-src 'self' data:; " +
                        "font-src 'self'; " +
                        "connect-src 'self'; " +
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
