namespace DailyQuran.Web.Quran;

/// <summary>
/// The surahs people most often come looking for, linked from the surah index
/// and the footer so they are always a tap — and, for search engines, a link —
/// away. Only numbers are kept here; names come from the surah index.
/// </summary>
public static class OftenRead
{
    public static readonly IReadOnlyList<int> Surahs = [1, 36, 18, 67, 55, 56];

    /// <summary>Al-Baqarah 2:255, known by a name of its own.</summary>
    public const string AyatAlKursiName = "Ayat al-Kursi";

    public static AyahRef AyatAlKursi(QuranLibrary library) => new(library.FindSurah(2)!, 255);
}
