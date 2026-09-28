using System.Text.RegularExpressions;

namespace DailyQuran.Web.Quran;

public enum RevelationPlace
{
    Unknown,
    Meccan,
    Medinan,
}

/// <summary>
/// A surah as the bundled index describes it: names, length and where it was
/// revealed. Reference data; it holds no Qur'an text.
/// </summary>
public sealed record Surah(
    int Number,
    string NameArabic,
    string NameTransliterated,
    string NameEnglish,
    int AyahCount,
    RevelationPlace RevelationPlace)
{
    public string RevelationLabel => RevelationPlace switch
    {
        RevelationPlace.Meccan => "Meccan",
        RevelationPlace.Medinan => "Medinan",
        _ => "",
    };

    /// <summary>
    /// Whether the basmala is set above the surah as a heading. Al-Fatihah
    /// opens with it as its first ayah, and At-Tawbah has none.
    /// </summary>
    public bool HasBasmalaHeading => Number is not (1 or 9);

    public string AyahCountLabel => AyahCount == 1 ? "1 ayah" : $"{AyahCount} ayat";
}

/// <summary>Where an edition's text came from, shown wherever it is read.</summary>
public sealed record EditionSource(string Name, string? Url, string? Translator, string? Licence);

/// <summary>
/// One readable edition from the catalog: the Uthmani Arabic with a
/// translation, or the Arabic alone.
/// </summary>
public sealed partial record Edition(
    string Id,
    string Title,
    string Translator,
    string Description,
    string LanguageName,
    string? LanguageNativeName,
    string LanguageCode,
    bool IsRightToLeft,
    bool HasTranslation,
    EditionSource Source)
{
    /// <summary>
    /// The title without the language the catalog adds in brackets:
    /// "Maududi (Urdu)" is "Maududi", "Arabic only (Uthmani)" is "Arabic only".
    /// </summary>
    public string ShortTitle => TrailingBrackets().Replace(Title, "");

    /// <summary>"English — Saheeh International", or "Arabic only".</summary>
    public string Label => HasTranslation ? $"{LanguageName} — {ShortTitle}" : "Arabic only";

    /// <summary>"French (Français)", or just "English".</summary>
    public string LanguageDisplay =>
        LanguageNativeName is { Length: > 0 } native && native != LanguageName
            ? $"{LanguageName} ({native})"
            : LanguageName;

    public string Direction => IsRightToLeft ? "rtl" : "ltr";

    /// <summary>The language alone, "ur" for "ur-PK": what hreflang and og:locale want.</summary>
    public string LanguageTag => LanguageCode.Split('-')[0].ToLowerInvariant();

    [GeneratedRegex(@"\s*\([^)]*\)\s*$")]
    private static partial Regex TrailingBrackets();
}

/// <summary>
/// One word of an ayah with the gloss the source gives it: a reading aid for
/// the Arabic, not a translation of the ayah.
/// </summary>
public sealed record Word(string Arabic, string Gloss);

/// <summary>An ayah as a reader sees it in one edition.</summary>
public sealed record AyahText(
    Surah Surah,
    int Number,
    string Arabic,
    string? Translation,
    IReadOnlyList<Word>? Words)
{
    public string Key => $"{Surah.Number}:{Number}";

    public string Reference => $"{Surah.NameTransliterated} {Key}";
}

/// <summary>An ayah's address, and the pages it lives on.</summary>
public sealed record AyahRef(Surah Surah, int Number)
{
    public string Key => $"{Surah.Number}:{Number}";

    public string Reference => $"{Surah.NameTransliterated} {Key}";

    /// <summary>The ayah's own page.</summary>
    public string PagePath => $"/quran/{Surah.Number}/{Number}";

    /// <summary>The ayah in its place in the surah.</summary>
    public string ReaderPath => $"/quran/{Surah.Number}#a{Number}";
}

/// <summary>One translation of one ayah.</summary>
public sealed record AyahTranslation(Edition Edition, string Text);

/// <summary>Where the word-by-word glosses came from, and what they are not.</summary>
public sealed record WordIndexInfo(string Notice, string LanguageName, EditionSource Source);
