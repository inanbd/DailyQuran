using DailyQuran.Web.Quran;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace DailyQuran.Web.Pages;

public sealed class IndexModel(QuranLibrary library, DailyAyah daily) : PageModel
{
    /// <summary>Al-Fatihah's first ayah, set above the page's title as it is set above a surah.</summary>
    public AyahText Basmala { get; private set; } = null!;

    public AyahText Today { get; private set; } = null!;

    public Edition TodayEdition { get; private set; } = null!;

    public IReadOnlyList<Edition> Editions => library.Editions;

    public void OnGet()
    {
        ReaderPreferences preferences = ReaderPreferences.Resolve(HttpContext, library);
        TodayEdition = preferences.TranslationOr(library.DefaultEdition);
        Today = daily.ForToday(TodayEdition);
        Basmala = library.GetAyah(1, 1, library.DefaultEdition);
    }
}
