using DailyQuran.Web.Quran;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace DailyQuran.Web.Pages.Reader;

/// <summary>
/// One ayah on a page of its own: the Arabic, word by word, and every
/// translation — the page someone lands on when they search for an ayah, and
/// the one a shared link opens.
/// </summary>
public sealed class AyahModel(QuranLibrary library) : PageModel
{
    public AyahRef Ref { get; private set; } = null!;

    /// <summary>The Arabic, with its words when the glosses are installed.</summary>
    public AyahText Ayah { get; private set; } = null!;

    /// <summary>Every translation, the reader's own first.</summary>
    public IReadOnlyList<AyahTranslation> Translations { get; private set; } = [];

    public AyahRef? Previous { get; private set; }

    public AyahRef? Next { get; private set; }

    public WordIndexInfo? WordIndex => library.WordIndex;

    public Edition DefaultEdition => library.DefaultEdition;

    public IActionResult OnGet(int surah, int ayah)
    {
        if (!library.Contains(surah, ayah))
        {
            return NotFound();
        }

        Ref = new AyahRef(library.FindSurah(surah)!, ayah);
        Ayah = library.GetAyah(surah, ayah, library.DefaultEdition, withWords: true);

        // Searchers arrive with no preference and see the default first; a
        // reader who chose a translation sees theirs first.
        Edition first = ReaderPreferences.Resolve(HttpContext, library).TranslationOr(library.DefaultEdition);
        Translations = library.TranslationsOf(surah, ayah, first);

        Previous = library.Before(surah, ayah);
        Next = library.After(surah, ayah);
        return Page();
    }
}
