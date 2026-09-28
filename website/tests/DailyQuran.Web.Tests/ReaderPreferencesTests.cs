using DailyQuran.Web.Quran;
using Microsoft.AspNetCore.Http;

namespace DailyQuran.Web.Tests;

public sealed class ReaderPreferencesTests(LibraryFixture fixture) : IClassFixture<LibraryFixture>
{
    private readonly QuranLibrary _library = fixture.Library;

    private static DefaultHttpContext Request(string query = "", string? cookie = null)
    {
        var http = new DefaultHttpContext();
        http.Request.QueryString = new QueryString(query);
        if (cookie is not null)
        {
            http.Request.Headers.Cookie = $"{ReaderPreferences.CookieName}={cookie}";
        }
        return http;
    }

    private static string? CookieSet(HttpContext http) =>
        http.Response.Headers.SetCookie.FirstOrDefault(c => c!.StartsWith(ReaderPreferences.CookieName + "=", StringComparison.Ordinal));

    [Fact]
    public void A_first_visit_reads_the_default_edition_and_sets_nothing()
    {
        DefaultHttpContext http = Request();
        ReaderPreferences preferences = ReaderPreferences.Resolve(http, _library);

        Assert.Equal("saheeh_international", preferences.Edition.Id);
        Assert.False(preferences.WordByWord);
        Assert.Null(CookieSet(http));
    }

    [Fact]
    public void Choosing_an_edition_remembers_it()
    {
        DefaultHttpContext http = Request("?t=hamidullah&wbw=1");
        ReaderPreferences preferences = ReaderPreferences.Resolve(http, _library);

        Assert.Equal("hamidullah", preferences.Edition.Id);
        Assert.True(preferences.WordByWord);
        string cookie = CookieSet(http)!;
        Assert.StartsWith($"{ReaderPreferences.CookieName}=hamidullah%7C1", cookie);
        Assert.Contains("httponly", cookie, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("samesite=lax", cookie, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void The_remembered_choice_opens_the_next_surah()
    {
        DefaultHttpContext http = Request(cookie: "maududi|1");
        ReaderPreferences preferences = ReaderPreferences.Resolve(http, _library);

        Assert.Equal("maududi", preferences.Edition.Id);
        Assert.True(preferences.WordByWord);
        Assert.Null(CookieSet(http));
    }

    [Fact]
    public void An_unchecked_box_after_its_hidden_default_turns_word_by_word_off()
    {
        // The settings form sends wbw=0 from a hidden field, then wbw=1 only when the box is ticked.
        Assert.False(ReaderPreferences.Resolve(Request("?t=kuliev&wbw=0", cookie: "kuliev|1"), _library).WordByWord);
        Assert.True(ReaderPreferences.Resolve(Request("?t=kuliev&wbw=0&wbw=1"), _library).WordByWord);
    }

    [Fact]
    public void An_unknown_edition_falls_back_rather_than_failing()
    {
        DefaultHttpContext http = Request("?t=not_an_edition", cookie: "also_not|0");
        Assert.Equal("saheeh_international", ReaderPreferences.Resolve(http, _library).Edition.Id);
        Assert.Null(CookieSet(http));
    }

    [Fact]
    public void The_Arabic_alone_borrows_the_default_translation_where_one_is_needed()
    {
        ReaderPreferences preferences = ReaderPreferences.Resolve(Request("?t=arabic_uthmani"), _library);
        Assert.False(preferences.Edition.HasTranslation);
        Assert.Equal("saheeh_international", preferences.TranslationOr(_library.DefaultEdition).Id);
    }
}
