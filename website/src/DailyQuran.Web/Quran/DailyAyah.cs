namespace DailyQuran.Web.Quran;

/// <summary>
/// The ayah the home page offers for the day: the same for every visitor on a
/// given date, and a different one the next. Drawn from ayat that stand on
/// their own, several of them about the Qur'an itself, so a single ayah read
/// out of its surah is not left mid-sentence. The site only chooses which
/// ayah; the text is the edition's own.
/// </summary>
public sealed class DailyAyah(QuranLibrary library, TimeProvider clock)
{
    internal static readonly (int Surah, int Ayah)[] Selection =
    [
        (2, 2), (2, 45), (2, 152), (2, 153), (2, 156), (2, 186), (2, 201),
        (2, 286), (3, 8), (3, 139), (3, 190), (7, 204), (12, 2), (13, 28),
        (14, 7), (17, 9), (20, 114), (29, 69), (33, 41), (38, 29), (39, 53),
        (40, 60), (47, 24), (50, 16), (54, 17), (94, 5), (112, 1),
    ];

    public AyahText ForToday(Edition edition)
    {
        int day = DateOnly.FromDateTime(clock.GetUtcNow().UtcDateTime).DayNumber;
        (int surah, int ayah) = Selection[day % Selection.Length];
        return library.GetAyah(surah, ayah, edition);
    }
}
