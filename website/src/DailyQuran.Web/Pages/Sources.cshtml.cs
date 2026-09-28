using DailyQuran.Web.Quran;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace DailyQuran.Web.Pages;

public sealed class SourcesModel(QuranLibrary library) : PageModel
{
    public IReadOnlyList<Edition> Editions => library.Editions;

    public WordIndexInfo? WordIndex => library.WordIndex;

    public static readonly IReadOnlyList<(string Name, string Use, string Licence)> Fonts =
    [
        ("Noto Naskh Arabic", "the Arabic, as in the app", "OFL-notonaskharabic.txt"),
        ("Amiri Quran", "the Arabic when chosen, and surah names", "OFL-amiriquran.txt"),
        ("Cormorant Garamond", "headings", "OFL-cormorantgaramond.txt"),
        ("Literata", "translations", "OFL-literata.txt"),
        ("Inter", "everything else, as in the app", "OFL-inter.txt"),
        ("Noto Nastaliq Urdu", "the Urdu translation", "OFL-notonastaliqurdu.txt"),
        ("Noto Serif Bengali", "the Bengali translation", "OFL-notoserifbengali.txt"),
    ];
}
