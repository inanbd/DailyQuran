using Markdig;
using Markdig.Syntax;
using Microsoft.AspNetCore.Html;

namespace DailyQuran.Web.Site;

/// <summary>
/// The app's privacy policy and its latest release notes, rendered from the
/// repository's own PRIVACY.md and CHANGELOG.md so the site never says
/// something different from what the app ships with.
/// </summary>
public sealed class SiteContent
{
    private static readonly MarkdownPipeline Pipeline = new MarkdownPipelineBuilder()
        .UseAutoLinks()
        .UseSmartyPants()
        .DisableHtml()
        .Build();

    private SiteContent(HtmlString privacyPolicy, ReleaseNotes? latestRelease)
    {
        PrivacyPolicy = privacyPolicy;
        LatestRelease = latestRelease;
    }

    /// <summary>PRIVACY.md without its title, its headings one level down so they sit under the page's own.</summary>
    public HtmlString PrivacyPolicy { get; }

    /// <summary>The newest section of CHANGELOG.md.</summary>
    public ReleaseNotes? LatestRelease { get; }

    public static SiteContent Load(string directory)
    {
        string privacyPath = Path.Combine(directory, "PRIVACY.md");
        string changelogPath = Path.Combine(directory, "CHANGELOG.md");

        HtmlString privacy = File.Exists(privacyPath)
            ? Render(DropTitle(File.ReadAllText(privacyPath)), headingShift: 1)
            : HtmlString.Empty;
        ReleaseNotes? latest = File.Exists(changelogPath)
            ? LatestSection(File.ReadAllLines(changelogPath))
            : null;

        return new SiteContent(privacy, latest);
    }

    private static string DropTitle(string markdown)
    {
        string[] lines = markdown.Split('\n');
        return string.Join('\n', lines.SkipWhile(l => !l.StartsWith("# ", StringComparison.Ordinal)).Skip(1));
    }

    /// <summary>The newest released version: an "Unreleased" section at the top is work not yet in anyone's hands.</summary>
    private static ReleaseNotes? LatestSection(string[] lines)
    {
        int start = Array.FindIndex(lines, l =>
            l.StartsWith("## ", StringComparison.Ordinal)
            && !l[3..].Trim().Equals("Unreleased", StringComparison.OrdinalIgnoreCase));
        if (start < 0)
        {
            return null;
        }
        int end = Array.FindIndex(lines, start + 1, l => l.StartsWith("## ", StringComparison.Ordinal));
        string body = string.Join('\n', lines[(start + 1)..(end < 0 ? lines.Length : end)]);
        return new ReleaseNotes(lines[start][3..].Trim(), Render(body, headingShift: 1));
    }

    private static HtmlString Render(string markdown, int headingShift)
    {
        MarkdownDocument document = Markdown.Parse(markdown, Pipeline);
        foreach (HeadingBlock heading in document.Descendants<HeadingBlock>())
        {
            heading.Level = Math.Min(6, heading.Level + headingShift);
        }
        return new HtmlString(document.ToHtml(Pipeline));
    }
}

public sealed record ReleaseNotes(string Version, HtmlString Html);
