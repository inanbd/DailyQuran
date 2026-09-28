using Microsoft.AspNetCore.Html;

namespace DailyQuran.Web.Site;

/// <summary>
/// The site's line icons: 24-unit, drawn with a 1.6 stroke in the current text
/// colour, so they sit in a line of text at its size and take its colour.
/// Decorative — every one is hidden from assistive technology, and the control
/// or text beside it carries the meaning.
/// </summary>
public static class Icon
{
    public static readonly HtmlString Book = Svg("<path d=\"M12 6.5C10 5 7.5 4.5 4 4.5v13c3.5 0 6 .5 8 2 2-1.5 4.5-2 8-2v-13c-3.5 0-6 .5-8 2Z\"/><path d=\"M12 6.5v13\"/>");
    public static readonly HtmlString Calendar = Svg("<rect x=\"3.5\" y=\"5\" width=\"17\" height=\"15\" rx=\"2.5\"/><path d=\"M3.5 9.5h17M8 3v4M16 3v4M8 13.5h2M14 13.5h2M8 16.5h2\"/>");
    public static readonly HtmlString Globe = Svg("<circle cx=\"12\" cy=\"12\" r=\"8.5\"/><path d=\"M3.5 12h17M12 3.5c2.5 2.6 3.5 5.4 3.5 8.5s-1 5.9-3.5 8.5c-2.5-2.6-3.5-5.4-3.5-8.5s1-5.9 3.5-8.5Z\"/>");
    public static readonly HtmlString Words = Svg("<rect x=\"3.5\" y=\"5\" width=\"7.5\" height=\"6\" rx=\"1.5\"/><rect x=\"13\" y=\"5\" width=\"7.5\" height=\"6\" rx=\"1.5\"/><path d=\"M4.5 15h5.5M14 15h5.5M4.5 18.5h3.5M14 18.5h3.5\"/>");
    public static readonly HtmlString Bell = Svg("<path d=\"M6 16.5V11a6 6 0 1 1 12 0v5.5l1.5 2h-15L6 16.5Z\"/><path d=\"M10 20.5a2 2 0 0 0 4 0\"/>");
    public static readonly HtmlString Star = Svg("<path d=\"M12 2l2.93 2.93h4.14v4.14L22 12l-2.93 2.93v4.14h-4.14L12 22l-2.93-2.93H4.93v-4.14L2 12l2.93-2.93V4.93h4.14Z\"/>");
    public static readonly HtmlString Progress = Svg("<path d=\"M4 19.5h16\"/><path d=\"m5.5 15.5 4-4 3 3 6-6.5\"/><path d=\"M15 8h3.5v3.5\"/>");
    public static readonly HtmlString Clock = Svg("<circle cx=\"12\" cy=\"12\" r=\"8.5\"/><path d=\"M12 7.5V12l3 2\"/>");
    public static readonly HtmlString Shield = Svg("<path d=\"M12 3.5 5 6v5.5c0 4.3 2.9 7.6 7 9 4.1-1.4 7-4.7 7-9V6l-7-2.5Z\"/><path d=\"m9 12 2 2 4-4\"/>");
    public static readonly HtmlString Volume = Svg("<path d=\"M4 9.5h3.5L12 6v12l-4.5-3.5H4Z\"/><path d=\"M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11\"/>");
    public static readonly HtmlString Heart = Svg("<path d=\"M12 19.5s-7.5-4.4-7.5-9.7A4.3 4.3 0 0 1 12 7.2a4.3 4.3 0 0 1 7.5 2.6c0 5.3-7.5 9.7-7.5 9.7Z\"/>");
    public static readonly HtmlString Phone = Svg("<rect x=\"7\" y=\"2.5\" width=\"10\" height=\"19\" rx=\"2.5\"/><path d=\"M11 18.5h2\"/>");
    public static readonly HtmlString NoAccount = Svg("<circle cx=\"10\" cy=\"8\" r=\"3.5\"/><path d=\"M3.5 19.5c.8-3.3 3.3-5 6.5-5s5.7 1.7 6.5 5\"/><path d=\"m16.5 5.5 4 4M20.5 5.5l-4 4\"/>");
    public static readonly HtmlString EyeOff = Svg("<path d=\"M3 3l18 18\"/><path d=\"M10.6 5.6A9.7 9.7 0 0 1 12 5.5c5 0 8.5 4.5 9.5 6.5a13 13 0 0 1-2.8 3.6M6.4 6.9C4.4 8.2 3.1 10.2 2.5 12c1 2 4.5 6.5 9.5 6.5 1.7 0 3.2-.5 4.5-1.2\"/><path d=\"M9.9 9.9a3 3 0 0 0 4.2 4.2\"/>");
    public static readonly HtmlString TextSize = Svg("<path d=\"M3 18 8 6l5 12M4.8 14h6.4\"/><path d=\"m14 18 3.5-8 3.5 8M15.2 15.5h4.6\"/>");
    public static readonly HtmlString Moon = Svg("<path d=\"M19.5 14.5A8 8 0 0 1 9.5 4.5a8 8 0 1 0 10 10Z\"/>");
    public static readonly HtmlString Sun = Svg("<circle cx=\"12\" cy=\"12\" r=\"4\"/><path d=\"M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4\"/>");
    public static readonly HtmlString Menu = Svg("<path d=\"M4 7h16M4 12h16M4 17h16\"/>");
    public static readonly HtmlString Close = Svg("<path d=\"M6 6l12 12M18 6 6 18\"/>");
    public static readonly HtmlString ArrowRight = Svg("<path d=\"M5 12h14M13 6l6 6-6 6\"/>");
    public static readonly HtmlString ArrowLeft = Svg("<path d=\"M19 12H5M11 6l-6 6 6 6\"/>");
    public static readonly HtmlString ChevronDown = Svg("<path d=\"m6 9 6 6 6-6\"/>");
    public static readonly HtmlString Copy = Svg("<rect x=\"8.5\" y=\"8.5\" width=\"11\" height=\"11\" rx=\"2\"/><path d=\"M15.5 8.5v-2a2 2 0 0 0-2-2h-7a2 2 0 0 0-2 2v7a2 2 0 0 0 2 2h2\"/>");
    public static readonly HtmlString Link = Svg("<path d=\"M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1\"/><path d=\"M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1\"/>");
    public static readonly HtmlString Sliders = Svg("<path d=\"M4 7h10M18 7h2M4 17h4M12 17h8\"/><circle cx=\"16\" cy=\"7\" r=\"2\"/><circle cx=\"10\" cy=\"17\" r=\"2\"/>");
    public static readonly HtmlString Search = Svg("<circle cx=\"11\" cy=\"11\" r=\"6.5\"/><path d=\"m20 20-4.2-4.2\"/>");
    public static readonly HtmlString Check = Svg("<path d=\"m5 12.5 4.5 4.5L19 7.5\"/>");
    public static readonly HtmlString Mail = Svg("<rect x=\"3.5\" y=\"5.5\" width=\"17\" height=\"13\" rx=\"2.5\"/><path d=\"m4.5 7 7.5 6 7.5-6\"/>");
    public static readonly HtmlString Download = Svg("<path d=\"M12 4v11M7 10.5l5 5 5-5M5 19.5h14\"/>");
    public static readonly HtmlString External = Svg("<path d=\"M14 4.5h5.5V10M19.5 4.5 11 13M18 14v4a2 2 0 0 1-2 2H6.5a2 2 0 0 1-2-2V8.5a2 2 0 0 1 2-2H10\"/>");
    public static readonly HtmlString Bookmark = Svg("<path d=\"M6.5 4.5h11v15.5L12 16l-5.5 4V4.5Z\"/>");

    private static HtmlString Svg(string body) =>
        new($"<svg class=\"icon\" viewBox=\"0 0 24 24\" aria-hidden=\"true\" focusable=\"false\">{body}</svg>");
}
