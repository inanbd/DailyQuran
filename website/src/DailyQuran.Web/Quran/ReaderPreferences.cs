using Microsoft.Extensions.Primitives;

namespace DailyQuran.Web.Quran;

/// <summary>
/// The two reading choices that change what the server renders: which edition,
/// and whether the Arabic is shown word by word. They arrive in the query
/// string (<c>?t=hamidullah&amp;wbw=1</c>) and are remembered in one small
/// first-party cookie, so the next surah opens the same way. Everything else a
/// reader can adjust — text size, script, theme — is presentation, and stays
/// in the browser.
/// </summary>
public sealed record ReaderPreferences(Edition Edition, bool WordByWord)
{
    public const string CookieName = "dq_reader";
    public const string EditionQuery = "t";
    public const string WordByWordQuery = "wbw";

    public static ReaderPreferences Resolve(HttpContext http, QuranLibrary library)
    {
        IQueryCollection query = http.Request.Query;
        (string? savedEdition, bool? savedWords) = ParseCookie(http.Request.Cookies[CookieName]);

        string? askedEdition = query.TryGetValue(EditionQuery, out StringValues t) ? t.LastOrDefault() : null;
        bool? askedWords = query.TryGetValue(WordByWordQuery, out StringValues w) ? ParseFlag(w.LastOrDefault()) : null;

        Edition edition = library.FindEdition(askedEdition) ?? library.FindEdition(savedEdition) ?? library.DefaultEdition;
        bool words = (askedWords ?? savedWords ?? false) && library.HasWordByWord;
        var preferences = new ReaderPreferences(edition, words);

        bool asked = library.FindEdition(askedEdition) is not null || askedWords is not null;
        if (asked && (edition.Id != savedEdition || words != savedWords))
        {
            http.Response.Cookies.Append(CookieName, $"{edition.Id}|{(words ? 1 : 0)}", new CookieOptions
            {
                MaxAge = TimeSpan.FromDays(365),
                HttpOnly = true,
                IsEssential = true,
                SameSite = SameSiteMode.Lax,
                Secure = http.Request.IsHttps,
            });
        }

        return preferences;
    }

    /// <summary>The edition to show a translation from: this one, or the default when this one is the Arabic alone.</summary>
    public Edition TranslationOr(Edition fallback) => Edition.HasTranslation ? Edition : fallback;

    private static (string?, bool?) ParseCookie(string? value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return (null, null);
        }
        int bar = value.IndexOf('|');
        return bar < 0 ? (value, null) : (value[..bar], ParseFlag(value[(bar + 1)..]));
    }

    private static bool? ParseFlag(string? value) => value?.ToLowerInvariant() switch
    {
        "1" or "on" or "true" or "yes" => true,
        "0" or "off" or "false" or "no" => false,
        _ => null,
    };
}
