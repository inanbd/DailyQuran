using DailyQuran.Web.Quran;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace DailyQuran.Web.Pages.Reader;

public sealed class IndexModel(QuranLibrary library) : PageModel
{
    public IReadOnlyList<Surah> Surahs => library.Surahs;

    public IReadOnlyList<Edition> Editions => library.Editions;

    public ReaderPreferences Preferences { get; private set; } = null!;

    public void OnGet() => Preferences = ReaderPreferences.Resolve(HttpContext, library);
}
