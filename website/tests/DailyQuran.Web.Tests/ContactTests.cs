using System.Net;
using DailyQuran.Web.Contact;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Time.Testing;
using MimeKit;

namespace DailyQuran.Web.Tests;

public sealed class ContactFormGuardTests
{
    private readonly FakeTimeProvider _clock = new(new DateTimeOffset(2026, 9, 27, 12, 0, 0, TimeSpan.Zero));
    private readonly ContactFormGuard _guard;

    public ContactFormGuardTests() => _guard = new ContactFormGuard(new EphemeralDataProtectionProvider(), _clock);

    [Fact]
    public void A_person_who_took_their_time_gets_through()
    {
        string token = _guard.IssueToken();
        _clock.Advance(TimeSpan.FromSeconds(40));
        Assert.Equal(GuardVerdict.Person, _guard.Check(token, honeypot: ""));
    }

    [Fact]
    public void Filling_the_hidden_field_marks_a_bot()
    {
        string token = _guard.IssueToken();
        _clock.Advance(TimeSpan.FromSeconds(40));
        Assert.Equal(GuardVerdict.Automated, _guard.Check(token, honeypot: "https://spam.example"));
    }

    [Fact]
    public void Sending_faster_than_anyone_could_type_marks_a_bot()
    {
        string token = _guard.IssueToken();
        _clock.Advance(TimeSpan.FromSeconds(1));
        Assert.Equal(GuardVerdict.Automated, _guard.Check(token, honeypot: null));
    }

    [Fact]
    public void A_missing_token_marks_a_bot()
    {
        Assert.Equal(GuardVerdict.Automated, _guard.Check(token: null, honeypot: null));
    }

    [Fact]
    public void A_form_left_open_for_a_day_has_expired()
    {
        string token = _guard.IssueToken();
        _clock.Advance(TimeSpan.FromDays(1));
        Assert.Equal(GuardVerdict.Expired, _guard.Check(token, honeypot: null));
    }

    [Fact]
    public void A_forged_token_is_not_trusted()
    {
        _clock.Advance(TimeSpan.FromMinutes(5));
        Assert.Equal(GuardVerdict.Expired, _guard.Check("forged-token", honeypot: null));
    }
}

public sealed class ContactEmailTests
{
    private static readonly ContactOptions Options = new()
    {
        Recipient = "Owner <owner@example.com>, second@example.com",
        Smtp = new SmtpOptions { Username = "site@example.com", FromName = "Daily Quran website" },
    };

    [Fact]
    public void Comes_from_the_site_and_replies_to_the_visitor()
    {
        var message = new ContactMessage("Aisha", "aisha@example.com", ContactTopic.Find("feedback")!, "A kind word about the app.", DateTimeOffset.UnixEpoch);
        MimeMessage email = ContactEmail.Compose(message, Options);

        Assert.Equal("site@example.com", email.From.Mailboxes.Single().Address);
        Assert.Equal(new[] { "owner@example.com", "second@example.com" }, email.To.Mailboxes.Select(m => m.Address));
        Assert.Equal("aisha@example.com", email.ReplyTo.Mailboxes.Single().Address);
        Assert.Equal("[Daily Quran] Feedback or an idea — from Aisha", email.Subject);
        Assert.Contains("A kind word about the app.", email.TextBody);
    }

    [Fact]
    public void A_name_cannot_smuggle_in_headers()
    {
        var message = new ContactMessage("Eve\r\nBcc: victim@example.com", "eve@example.com", ContactTopic.All[0], "Hello there, friends.", DateTimeOffset.UnixEpoch);
        MimeMessage email = ContactEmail.Compose(message, Options);

        Assert.DoesNotContain('\n', email.Subject!);
        Assert.Empty(email.Bcc);
        Assert.Equal("EveBcc: victim@example.com", email.ReplyTo.Mailboxes.Single().Name);
    }
}

/// <summary>
/// Opens the contact form and fills it in as a person would, half a minute later.
/// Each test class gets its own site, and so its own allowance of five posts
/// before the rate limiter steps in; keep each class under that.
/// </summary>
internal static class ContactForm
{
    public static async Task<(HttpClient Client, Dictionary<string, string> Form)> OpenAsync(SiteFactory site)
    {
        HttpClient client = site.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });
        string page = await client.GetStringAsync("/contact");
        var form = new Dictionary<string, string>
        {
            ["__RequestVerificationToken"] = Html.HiddenValue(page, "__RequestVerificationToken"),
            ["FormToken"] = Html.HiddenValue(page, "FormToken"),
            ["Website"] = "",
            ["Input.Name"] = "Yusuf",
            ["Input.Email"] = "yusuf@example.com",
            ["Input.Topic"] = "question",
            ["Input.Message"] = "Is there a way to read two translations at once?",
        };
        site.Clock.Advance(TimeSpan.FromSeconds(30));
        return (client, form);
    }
}

public sealed class ContactAccessTests : IClassFixture<SiteFactory>
{
    private readonly SiteFactory _site;

    public ContactAccessTests(SiteFactory site) => _site = site;

    [Fact]
    public async Task Asking_for_access_arrives_with_the_topic_already_chosen()
    {
        string page = System.Net.WebUtility.HtmlDecode(await _site.CreateClient().GetStringAsync("/contact?topic=access"));

        Assert.Contains("<option value=\"access\" selected=\"selected\">Access to the Android app</option>", page);
        Assert.Contains("Want the Android app?", page);
        Assert.Contains("the Gmail address", page);
    }

    [Fact]
    public async Task A_request_for_access_is_emailed_under_its_own_topic()
    {
        (HttpClient client, Dictionary<string, string> form) = await ContactForm.OpenAsync(_site);
        form["Input.Topic"] = "access";
        form["Input.Message"] = "Please add me as a tester: tester@gmail.com";

        HttpResponseMessage response = await client.PostAsync("/contact", new FormUrlEncodedContent(form));

        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        ContactMessage sent = Assert.Single(_site.Mailer.Sent, m => m.Message == "Please add me as a tester: tester@gmail.com");
        Assert.Equal("Access to the Android app", sent.Topic.Label);
    }
}

public sealed class ContactPageTests : IClassFixture<SiteFactory>
{
    private readonly SiteFactory _site;

    public ContactPageTests(SiteFactory site) => _site = site;

    private Task<(HttpClient Client, Dictionary<string, string> Form)> OpenForm() => ContactForm.OpenAsync(_site);

    [Fact]
    public async Task A_message_is_emailed_and_the_sender_thanked()
    {
        (HttpClient client, Dictionary<string, string> form) = await OpenForm();
        form["Input.Message"] = "A message that should arrive.";

        HttpResponseMessage response = await client.PostAsync("/contact", new FormUrlEncodedContent(form));

        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        Assert.Equal("/contact?sent=True", response.Headers.Location!.OriginalString);
        ContactMessage sent = Assert.Single(_site.Mailer.Sent, m => m.Message == "A message that should arrive.");
        Assert.Equal("Yusuf", sent.Name);
        Assert.Equal("yusuf@example.com", sent.Email);
        Assert.Equal("question", sent.Topic.Key);

        string thanks = await client.GetStringAsync("/contact?sent=True");
        Assert.Contains("your message is on its way", thanks);
    }

    [Fact]
    public async Task A_bot_is_thanked_but_nothing_is_sent()
    {
        (HttpClient client, Dictionary<string, string> form) = await OpenForm();
        form["Website"] = "https://spam.example";
        form["Input.Message"] = "Buy cheap things from a bot.";

        HttpResponseMessage response = await client.PostAsync("/contact", new FormUrlEncodedContent(form));

        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        Assert.DoesNotContain(_site.Mailer.Sent, m => m.Message == "Buy cheap things from a bot.");
    }

    [Fact]
    public async Task Mistakes_are_explained_and_what_was_typed_is_kept()
    {
        (HttpClient client, Dictionary<string, string> form) = await OpenForm();
        form["Input.Email"] = "not an email";
        form["Input.Message"] = "Short";

        HttpResponseMessage response = await client.PostAsync("/contact", new FormUrlEncodedContent(form));
        string page = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("look like an email address", page);
        Assert.Contains("at least a few words", page);
        Assert.Contains("value=\"Yusuf\"", page);
    }

    [Fact]
    public async Task A_post_without_the_antiforgery_token_is_refused()
    {
        (HttpClient client, Dictionary<string, string> form) = await OpenForm();
        form.Remove("__RequestVerificationToken");

        HttpResponseMessage response = await client.PostAsync("/contact", new FormUrlEncodedContent(form));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }
}

public sealed class ContactRateLimitTests : IClassFixture<SiteFactory>
{
    private readonly SiteFactory _site;

    public ContactRateLimitTests(SiteFactory site) => _site = site;

    [Fact]
    public async Task A_sixth_message_in_a_quarter_hour_is_asked_to_wait()
    {
        HttpClient client = _site.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false });
        string page = await client.GetStringAsync("/contact");
        _site.Clock.Advance(TimeSpan.FromSeconds(30));
        var form = new Dictionary<string, string>
        {
            ["__RequestVerificationToken"] = Html.HiddenValue(page, "__RequestVerificationToken"),
            ["FormToken"] = Html.HiddenValue(page, "FormToken"),
            ["Input.Name"] = "Hasty",
            ["Input.Email"] = "hasty@example.com",
            ["Input.Topic"] = "other",
            ["Input.Message"] = "One of several messages.",
        };

        for (int i = 0; i < 5; i++)
        {
            HttpResponseMessage accepted = await client.PostAsync("/contact", new FormUrlEncodedContent(form));
            Assert.Equal("/contact?sent=True", accepted.Headers.Location!.OriginalString);
        }
        HttpResponseMessage refused = await client.PostAsync("/contact", new FormUrlEncodedContent(form));

        Assert.Equal(HttpStatusCode.SeeOther, refused.StatusCode);
        Assert.Equal("/contact?busy=true", refused.Headers.Location!.OriginalString);
        Assert.Equal(5, _site.Mailer.Sent.Count);
        Assert.Contains("wait a few minutes", await client.GetStringAsync("/contact?busy=true"));
    }
}

public sealed class ContactWithoutMailTests : IClassFixture<SiteWithoutMailFactory>
{
    private readonly SiteWithoutMailFactory _site;

    public ContactWithoutMailTests(SiteWithoutMailFactory site) => _site = site;

    [Fact]
    public async Task An_unconfigured_form_says_so_instead_of_pretending()
    {
        string page = await _site.CreateClient().GetStringAsync("/contact");
        Assert.Contains("can’t be sent from this page just now", page);
    }
}
