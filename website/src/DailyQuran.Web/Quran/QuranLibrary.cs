using System.Text.Json;

namespace DailyQuran.Web.Quran;

/// <summary>
/// The whole Qur'an, every verified edition and the word index, held in
/// memory. It reads the same JSON files the app bundles (see DATA_SOURCES.md)
/// and, like the app, copies text verbatim: an ayah a source leaves without a
/// translation is shown without one.
/// </summary>
/// <remarks>
/// Ayat are stored by reading position, so the Arabic is kept once rather than
/// in every edition, and each translation is one array beside it.
/// </remarks>
public sealed class QuranLibrary
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    private readonly int[] _surahStart;
    private readonly string[] _arabic;
    private readonly Dictionary<string, string?[]> _translations;
    private readonly Dictionary<string, Edition> _editionsById;
    private readonly Word[]?[]? _words;

    private QuranLibrary(
        Surah[] surahs,
        int[] surahStart,
        string[] arabic,
        Edition[] editions,
        Dictionary<string, string?[]> translations,
        Edition defaultEdition,
        Word[]?[]? words,
        WordIndexInfo? wordIndex)
    {
        Surahs = surahs;
        _surahStart = surahStart;
        _arabic = arabic;
        Editions = editions;
        _translations = translations;
        _editionsById = editions.ToDictionary(e => e.Id, StringComparer.OrdinalIgnoreCase);
        DefaultEdition = defaultEdition;
        _words = words;
        WordIndex = wordIndex;
    }

    public IReadOnlyList<Surah> Surahs { get; }

    /// <summary>Translations by language, then the Arabic alone.</summary>
    public IReadOnlyList<Edition> Editions { get; }

    public Edition DefaultEdition { get; }

    public WordIndexInfo? WordIndex { get; }

    public bool HasWordByWord => _words is not null;

    public int TotalAyah => _arabic.Length;

    public IEnumerable<Edition> Translations => Editions.Where(e => e.HasTranslation);

    public Surah? FindSurah(int number) =>
        number >= 1 && number <= Surahs.Count ? Surahs[number - 1] : null;

    public Edition? FindEdition(string? id) =>
        id is not null && _editionsById.TryGetValue(id, out Edition? edition) ? edition : null;

    public bool Contains(int surah, int ayah) =>
        FindSurah(surah) is { } found && ayah >= 1 && ayah <= found.AyahCount;

    /// <summary>The ayah's position in reading order, from 1 (1:1) to 6,236 (114:6).</summary>
    public int ReadingPosition(int surah, int ayah) => Ordinal(surah, ayah) + 1;

    /// <summary>The ayah at a reading position: 262 is 2:255.</summary>
    public AyahRef AtPosition(int position)
    {
        if (position < 1 || position > TotalAyah)
        {
            throw new ArgumentOutOfRangeException(nameof(position));
        }
        int ordinal = position - 1;
        int low = 1, high = Surahs.Count;
        while (low < high)
        {
            int middle = (low + high + 1) / 2;
            if (_surahStart[middle] <= ordinal)
            {
                low = middle;
            }
            else
            {
                high = middle - 1;
            }
        }
        return new AyahRef(Surahs[low - 1], ordinal - _surahStart[low] + 1);
    }

    /// <summary>The ayah before this one in reading order, across surahs; null before 1:1.</summary>
    public AyahRef? Before(int surah, int ayah)
    {
        int position = ReadingPosition(surah, ayah);
        return position > 1 ? AtPosition(position - 1) : null;
    }

    /// <summary>The ayah after this one in reading order, across surahs; null after 114:6.</summary>
    public AyahRef? After(int surah, int ayah)
    {
        int position = ReadingPosition(surah, ayah);
        return position < TotalAyah ? AtPosition(position + 1) : null;
    }

    /// <summary>
    /// This ayah in every translation, <paramref name="first"/> leading and the
    /// rest in library order. An edition with no text for the ayah is left out.
    /// </summary>
    public IReadOnlyList<AyahTranslation> TranslationsOf(int surah, int ayah, Edition? first = null)
    {
        int ordinal = Ordinal(surah, ayah);
        return Translations
            .OrderBy(e => first is not null && e.Id == first.Id ? 0 : 1)
            .Select(e => _translations[e.Id][ordinal] is { } text ? new AyahTranslation(e, text) : null)
            .OfType<AyahTranslation>()
            .ToArray();
    }

    public AyahText GetAyah(int surah, int ayah, Edition edition, bool withWords = false)
    {
        Surah found = FindSurah(surah) ?? throw new ArgumentOutOfRangeException(nameof(surah));
        return Build(found, ayah, edition, withWords);
    }

    public IReadOnlyList<AyahText> GetSurah(int surah, Edition edition, bool withWords = false)
    {
        Surah found = FindSurah(surah) ?? throw new ArgumentOutOfRangeException(nameof(surah));
        var ayat = new AyahText[found.AyahCount];
        for (int i = 0; i < ayat.Length; i++)
        {
            ayat[i] = Build(found, i + 1, edition, withWords);
        }
        return ayat;
    }

    private AyahText Build(Surah surah, int ayah, Edition edition, bool withWords)
    {
        int ordinal = Ordinal(surah.Number, ayah);
        string? translation = _translations.TryGetValue(edition.Id, out string?[]? texts) ? texts[ordinal] : null;
        IReadOnlyList<Word>? words = withWords && _words?[ordinal] is { Length: > 0 } glossed ? glossed : null;
        return new AyahText(surah, ayah, _arabic[ordinal], translation, words);
    }

    private int Ordinal(int surah, int ayah)
    {
        if (!Contains(surah, ayah))
        {
            throw new ArgumentOutOfRangeException(nameof(ayah), $"{surah}:{ayah} is not an ayah of the Qur'an.");
        }
        return _surahStart[surah] + ayah - 1;
    }

    /// <summary>
    /// Reads the data directory: <c>surahs.json</c>, <c>catalog.json</c>, every
    /// verified edition under <c>editions/</c>, and <c>word_by_word.json</c>
    /// if it is there. An edition listed in the catalog without a file is
    /// skipped, as the app skips it.
    /// </summary>
    public static QuranLibrary Load(string directory, string defaultEditionId)
    {
        SurahIndexFile index = Read<SurahIndexFile>(Path.Combine(directory, "surahs.json"));
        Surah[] surahs = index.Surahs.Select(ToSurah).ToArray();
        for (int i = 0; i < surahs.Length; i++)
        {
            if (surahs[i].Number != i + 1)
            {
                throw new InvalidDataException($"surahs.json lists surah {surahs[i].Number} in position {i + 1}.");
            }
        }

        // _surahStart[n] is the reading position of surah n's first ayah, counting from 0.
        var surahStart = new int[surahs.Length + 2];
        for (int n = 1; n <= surahs.Length; n++)
        {
            surahStart[n + 1] = surahStart[n] + surahs[n - 1].AyahCount;
        }
        int total = surahStart[surahs.Length + 1];

        CatalogFile catalog = Read<CatalogFile>(Path.Combine(directory, "catalog.json"));
        CatalogEdition[] available = catalog.Editions
            .Where(e => e.Verification == "verified")
            .Where(e => File.Exists(EditionPath(directory, e)))
            .ToArray();
        if (available.Length == 0)
        {
            throw new InvalidDataException($"No verified edition was found under {Path.Combine(directory, "editions")}.");
        }

        var loaded = new (string?[] Arabic, string?[] Translation)[available.Length];
        Parallel.For(0, available.Length, i =>
        {
            EditionFile file = Read<EditionFile>(EditionPath(directory, available[i]));
            var arabic = new string?[total];
            var translation = new string?[total];
            foreach (EditionAyah entry in file.Ayat)
            {
                if (entry.Surah < 1 || entry.Surah > surahs.Length || entry.Ayah < 1 || entry.Ayah > surahs[entry.Surah - 1].AyahCount)
                {
                    throw new InvalidDataException($"{available[i].Slug}.json has an ayah {entry.Surah}:{entry.Ayah}, which the surah index does not.");
                }
                int ordinal = surahStart[entry.Surah] + entry.Ayah - 1;
                arabic[ordinal] = Text(entry.Arabic);
                translation[ordinal] = Text(entry.Translation);
            }
            loaded[i] = (arabic, translation);
        });

        // Every edition carries the same Uthmani text; the Arabic-only edition
        // is the natural one to take it from.
        int arabicSource = Array.FindIndex(available, e => e.Id == "arabic_uthmani");
        string?[] arabicText = loaded[arabicSource >= 0 ? arabicSource : 0].Arabic;
        string[] arabicAll = arabicText.Select(a => a ?? "").ToArray();

        var editions = new List<Edition>();
        var translations = new Dictionary<string, string?[]>(StringComparer.OrdinalIgnoreCase);
        for (int i = 0; i < available.Length; i++)
        {
            CatalogEdition entry = available[i];
            bool hasTranslation = loaded[i].Translation.Any(t => t is not null);
            editions.Add(new Edition(
                Id: entry.Id,
                Title: entry.TitleEnglish,
                Translator: entry.Translator ?? "",
                Description: entry.Description ?? "",
                LanguageName: entry.LanguageName ?? "",
                LanguageNativeName: entry.LanguageNativeName,
                LanguageCode: entry.LanguageCode ?? "en",
                IsRightToLeft: string.Equals(entry.LanguageDirection, "rtl", StringComparison.OrdinalIgnoreCase),
                HasTranslation: hasTranslation,
                Source: ToSource(entry.Source)));
            if (hasTranslation)
            {
                translations[entry.Id] = loaded[i].Translation;
            }
        }

        Edition[] ordered = editions
            .OrderBy(e => e.HasTranslation ? 0 : 1)
            .ThenBy(e => e.LanguageName, StringComparer.Ordinal)
            .ThenBy(e => e.Title, StringComparer.Ordinal)
            .ToArray();
        Edition defaultEdition = ordered.FirstOrDefault(e => e.Id == defaultEditionId)
            ?? ordered.FirstOrDefault(e => e.HasTranslation)
            ?? ordered[0];

        (Word[]?[]? words, WordIndexInfo? wordIndex) = LoadWords(directory, surahs, surahStart, total);

        return new QuranLibrary(surahs, surahStart, arabicAll, ordered, translations, defaultEdition, words, wordIndex);
    }

    private static (Word[]?[]?, WordIndexInfo?) LoadWords(string directory, Surah[] surahs, int[] surahStart, int total)
    {
        string path = Path.Combine(directory, "word_by_word.json");
        if (!File.Exists(path))
        {
            // Removing the file is how the glosses are withdrawn (see
            // DATA_SOURCES.md); the reader then simply has no word-by-word view.
            return (null, null);
        }

        WordIndexFile file = Read<WordIndexFile>(path);
        var words = new Word[]?[total];
        foreach ((string key, WordEntry[] entries) in file.Words)
        {
            int colon = key.IndexOf(':');
            if (colon <= 0
                || !int.TryParse(key.AsSpan(0, colon), out int surah)
                || !int.TryParse(key.AsSpan(colon + 1), out int ayah)
                || surah < 1 || surah > surahs.Length
                || ayah < 1 || ayah > surahs[surah - 1].AyahCount)
            {
                continue;
            }
            Word[] kept = entries
                .Where(w => Text(w.Arabic) is not null || Text(w.Translation) is not null)
                .Select(w => new Word(Text(w.Arabic) ?? "", Text(w.Translation) ?? ""))
                .ToArray();
            words[surahStart[surah] + ayah - 1] = kept;
        }

        var info = new WordIndexInfo(file.Notice ?? "", file.LanguageName ?? "English", ToSource(file.Source));
        return (words, info);
    }

    private static string EditionPath(string directory, CatalogEdition edition) =>
        Path.Combine(directory, "editions", $"{edition.Slug ?? edition.Id}.json");

    /// <summary>Whitespace-only strings are absent, as they are in the app.</summary>
    private static string? Text(string? value) => string.IsNullOrWhiteSpace(value) ? null : value;

    private static Surah ToSurah(SurahEntry s) => new(
        s.Number,
        s.NameArabic,
        s.NameTransliterated,
        s.NameEnglish,
        s.AyahCount,
        s.RevelationPlace?.ToLowerInvariant() switch
        {
            "meccan" => RevelationPlace.Meccan,
            "medinan" => RevelationPlace.Medinan,
            _ => RevelationPlace.Unknown,
        });

    private static EditionSource ToSource(SourceEntry? source) =>
        new(source?.Name ?? "", source?.Url, source?.Translator, source?.Licence);

    private static T Read<T>(string path)
    {
        using FileStream stream = File.OpenRead(path);
        return JsonSerializer.Deserialize<T>(stream, Json)
            ?? throw new InvalidDataException($"{path} is empty.");
    }

    // The shapes documented in DATA_SOURCES.md, keeping only what the site reads.

    private sealed record SurahIndexFile(SurahEntry[] Surahs);

    private sealed record SurahEntry(
        int Number,
        string NameArabic,
        string NameTransliterated,
        string NameEnglish,
        int AyahCount,
        string? RevelationPlace);

    private sealed record CatalogFile(CatalogEdition[] Editions);

    private sealed record CatalogEdition(
        string Id,
        string? Slug,
        string TitleEnglish,
        string? Translator,
        string? Description,
        string? LanguageName,
        string? LanguageNativeName,
        string? LanguageCode,
        string? LanguageDirection,
        string? Verification,
        SourceEntry? Source);

    private sealed record SourceEntry(string? Name, string? Url, string? Translator, string? Licence);

    private sealed record EditionFile(EditionAyah[] Ayat);

    private sealed record EditionAyah(int Surah, int Ayah, string? Arabic, string? Translation);

    private sealed record WordIndexFile(
        string? Notice,
        string? LanguageName,
        SourceEntry? Source,
        Dictionary<string, WordEntry[]> Words);

    private sealed record WordEntry(string? Arabic, string? Translation);
}
