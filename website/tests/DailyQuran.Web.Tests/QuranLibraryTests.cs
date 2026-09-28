using DailyQuran.Web.Quran;
using Microsoft.Extensions.Time.Testing;

namespace DailyQuran.Web.Tests;

public sealed class QuranLibraryTests(LibraryFixture fixture) : IClassFixture<LibraryFixture>
{
    private readonly QuranLibrary _library = fixture.Library;

    [Fact]
    public void Holds_the_whole_Quran_in_the_standard_numbering()
    {
        Assert.Equal(114, _library.Surahs.Count);
        Assert.Equal(6236, _library.TotalAyah);
        Assert.Equal(6236, _library.Surahs.Sum(s => s.AyahCount));
    }

    [Fact]
    public void Places_Ayat_al_Kursi_at_reading_position_262()
    {
        // The same check the app's smoke test makes: an off-by-one anywhere shows up here.
        Assert.Equal(262, _library.ReadingPosition(2, 255));
        Assert.Equal(1, _library.ReadingPosition(1, 1));
        Assert.Equal(6236, _library.ReadingPosition(114, 6));
    }

    [Fact]
    public void Serves_every_verified_edition_and_never_the_development_fixture()
    {
        Assert.Equal(7, _library.Editions.Count);
        Assert.Null(_library.FindEdition("dev_sample"));
        Assert.All(
            new[] { "arabic_uthmani", "saheeh_international", "maududi", "hamidullah", "garcia", "kuliev", "muhiuddin_khan" },
            id => Assert.NotNull(_library.FindEdition(id)));
    }

    [Fact]
    public void Lists_translations_by_language_then_the_Arabic_alone()
    {
        Assert.Equal(
            new[] { "Bengali", "English", "French", "Russian", "Spanish", "Urdu" },
            _library.Translations.Select(e => e.LanguageName));
        Assert.False(_library.Editions[^1].HasTranslation);
        Assert.Equal("Arabic only", _library.Editions[^1].Label);
        Assert.Equal("saheeh_international", _library.DefaultEdition.Id);
    }

    [Fact]
    public void Every_translation_is_complete_and_every_ayah_has_its_Arabic()
    {
        foreach (Edition edition in _library.Translations)
        {
            foreach (Surah surah in _library.Surahs)
            {
                IReadOnlyList<AyahText> ayat = _library.GetSurah(surah.Number, edition);
                Assert.All(ayat, ayah =>
                {
                    Assert.False(string.IsNullOrWhiteSpace(ayah.Arabic), $"{ayah.Key} has no Arabic");
                    Assert.False(string.IsNullOrWhiteSpace(ayah.Translation), $"{ayah.Key} has no {edition.Id} translation");
                });
            }
        }
    }

    [Fact]
    public void The_Arabic_is_the_same_in_every_edition()
    {
        AyahText english = _library.GetAyah(2, 255, _library.FindEdition("saheeh_international")!);
        AyahText arabicOnly = _library.GetAyah(2, 255, _library.FindEdition("arabic_uthmani")!);
        Assert.Equal(arabicOnly.Arabic, english.Arabic);
        Assert.Null(arabicOnly.Translation);
    }

    [Fact]
    public void Right_to_left_translations_say_so()
    {
        Assert.True(_library.FindEdition("maududi")!.IsRightToLeft);
        Assert.Equal("rtl", _library.FindEdition("maududi")!.Direction);
        Assert.False(_library.FindEdition("hamidullah")!.IsRightToLeft);
    }

    [Fact]
    public void Word_by_word_glosses_are_joined_on_only_when_asked_for()
    {
        Edition english = _library.DefaultEdition;
        Assert.True(_library.HasWordByWord);
        Assert.Null(_library.GetAyah(1, 2, english).Words);

        IReadOnlyList<Word> words = _library.GetAyah(1, 2, english, withWords: true).Words!;
        Assert.Equal(4, words.Count);
        Assert.All(words, word =>
        {
            Assert.NotEmpty(word.Arabic);
            Assert.NotEmpty(word.Gloss);
        });
        Assert.Contains("not a translation", _library.WordIndex!.Notice);
    }

    [Theory]
    [InlineData(0, 1)]
    [InlineData(115, 1)]
    [InlineData(1, 0)]
    [InlineData(1, 8)]
    [InlineData(2, 287)]
    public void Refuses_an_ayah_that_is_not_in_the_Quran(int surah, int ayah)
    {
        Assert.False(_library.Contains(surah, ayah));
    }

    [Fact]
    public void Knows_which_surahs_carry_the_basmala_as_a_heading()
    {
        Assert.False(_library.FindSurah(1)!.HasBasmalaHeading);
        Assert.False(_library.FindSurah(9)!.HasBasmalaHeading);
        Assert.True(_library.FindSurah(2)!.HasBasmalaHeading);
        Assert.True(_library.FindSurah(114)!.HasBasmalaHeading);
    }

    [Fact]
    public void The_ayah_for_today_is_always_a_real_ayah()
    {
        Assert.All(DailyAyah.Selection, pick => Assert.True(_library.Contains(pick.Surah, pick.Ayah), $"{pick.Surah}:{pick.Ayah}"));
        Assert.Equal(DailyAyah.Selection.Length, DailyAyah.Selection.Distinct().Count());
    }

    [Fact]
    public void The_ayah_for_today_holds_all_day_and_changes_the_next()
    {
        var clock = new FakeTimeProvider(new DateTimeOffset(2026, 9, 27, 0, 5, 0, TimeSpan.Zero));
        var daily = new DailyAyah(_library, clock);

        string morning = daily.ForToday(_library.DefaultEdition).Key;
        clock.Advance(TimeSpan.FromHours(23));
        Assert.Equal(morning, daily.ForToday(_library.DefaultEdition).Key);
        clock.Advance(TimeSpan.FromHours(1));
        Assert.NotEqual(morning, daily.ForToday(_library.DefaultEdition).Key);
    }
}
