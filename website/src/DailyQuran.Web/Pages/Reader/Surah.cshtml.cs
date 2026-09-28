using DailyQuran.Web.Quran;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace DailyQuran.Web.Pages.Reader;

public sealed class SurahModel(QuranLibrary library) : PageModel
{
    public Surah Surah { get; private set; } = null!;

    public Surah? Previous { get; private set; }

    public Surah? Next { get; private set; }

    public ReaderPreferences Preferences { get; private set; } = null!;

    public IReadOnlyList<AyahText> Ayat { get; private set; } = [];

    /// <summary>The basmala set above the surah, taken from Al-Fatihah's first ayah; null for Al-Fatihah and At-Tawbah.</summary>
    public string? Basmala { get; private set; }

    /// <summary>Where the surah falls in reading order: its first and last reading positions.</summary>
    public (int First, int Last) Positions { get; private set; }

    public IReadOnlyList<Surah> Surahs => library.Surahs;

    public IReadOnlyList<Edition> Editions => library.Editions;

    public bool WordByWordAvailable => library.HasWordByWord;

    public WordIndexInfo? WordIndex => library.WordIndex;

    public Edition DefaultEdition => library.DefaultEdition;

    /// <summary>This surah's address in <paramref name="edition"/>: the plain one for the default, <c>?t=</c> for the rest.</summary>
    public string PathIn(Edition edition) =>
        edition.Id == library.DefaultEdition.Id ? $"/quran/{Surah.Number}" : $"/quran/{Surah.Number}?t={edition.Id}";

    public IActionResult OnGet(int surah)
    {
        if (library.FindSurah(surah) is not { } found)
        {
            return NotFound();
        }

        Surah = found;
        Previous = library.FindSurah(surah - 1);
        Next = library.FindSurah(surah + 1);
        Preferences = ReaderPreferences.Resolve(HttpContext, library);
        Ayat = library.GetSurah(surah, Preferences.Edition, Preferences.WordByWord);
        Basmala = found.HasBasmalaHeading ? library.GetAyah(1, 1, library.DefaultEdition).Arabic : null;
        Positions = (library.ReadingPosition(surah, 1), library.ReadingPosition(surah, found.AyahCount));
        return Page();
    }
}
