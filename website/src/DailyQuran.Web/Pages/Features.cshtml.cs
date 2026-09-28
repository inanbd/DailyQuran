using DailyQuran.Web.Quran;
using DailyQuran.Web.Site;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace DailyQuran.Web.Pages;

public sealed class FeaturesModel(QuranLibrary library, SiteContent content) : PageModel
{
    public IEnumerable<Edition> Translations => library.Translations;

    public Edition? ArabicOnly => library.Editions.FirstOrDefault(e => !e.HasTranslation);

    /// <summary>Al-Fatihah 1:2 word by word, as the reader would see it; null when no glosses are installed.</summary>
    public AyahText? WordSample { get; private set; }

    public Edition SampleEdition { get; private set; } = null!;

    public ReleaseNotes? LatestRelease => content.LatestRelease;

    public void OnGet()
    {
        SampleEdition = ReaderPreferences.Resolve(HttpContext, library).TranslationOr(library.DefaultEdition);
        AyahText sample = library.GetAyah(1, 2, SampleEdition, withWords: true);
        WordSample = sample.Words is null ? null : sample;
    }
}
