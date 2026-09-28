using MimeKit;

namespace DailyQuran.Web.Contact;

/// <summary>What a visitor wrote, ready to be emailed.</summary>
public sealed record ContactMessage(string Name, string Email, ContactTopic Topic, string Message, DateTimeOffset SentAt);

public sealed record ContactTopic(string Key, string Label)
{
    /// <summary>Asking to be added as a tester, while the app is in internal testing on Google Play.</summary>
    public static readonly ContactTopic AppAccess = new("access", "Access to the Android app");

    private static readonly ContactTopic[] Standard =
    [
        new("question", "A question"),
        new("feedback", "Feedback or an idea"),
        new("app", "A problem with the app"),
        new("text", "A mistake in the Qur'an text or a translation"),
        new("website", "A problem with this website"),
        new("other", "Something else"),
    ];

    public static readonly IReadOnlyList<ContactTopic> All = [.. Standard, AppAccess];

    /// <summary>The topics the form lists: asking for access comes first while the app is in testing, and is not offered after.</summary>
    public static IReadOnlyList<ContactTopic> Offered(bool appInTesting) =>
        appInTesting ? [AppAccess, .. Standard] : Standard;

    public static ContactTopic? Find(string? key) => All.FirstOrDefault(t => t.Key == key);
}

public static class ContactEmail
{
    /// <summary>
    /// The email that carries a message to the site's owner. It is sent from
    /// the site's own address — the visitor's could not pass SPF or DKIM — with
    /// the visitor as Reply-To, so answering it reaches them.
    /// </summary>
    public static MimeMessage Compose(ContactMessage message, ContactOptions options)
    {
        string name = Clean(message.Name);
        var email = new MimeMessage();
        email.From.Add(new MailboxAddress(options.Smtp.FromName, options.Smtp.SenderAddress.Length > 0 ? options.Smtp.SenderAddress : "website@localhost"));
        email.To.AddRange(InternetAddressList.Parse(options.Recipient));
        email.ReplyTo.Add(new MailboxAddress(name, message.Email.Trim()));
        email.Subject = $"[Daily Quran] {message.Topic.Label} — from {name}";
        email.Body = new TextPart("plain")
        {
            Text =
                $"""
                {name} <{message.Email.Trim()}> wrote through the Daily Quran website.

                Topic: {message.Topic.Label}
                Sent:  {message.SentAt:dddd d MMMM yyyy, HH:mm} UTC

                ------------------------------------------------------------

                {message.Message.Trim()}

                ------------------------------------------------------------
                Reply to this email to answer {name} directly.
                """,
        };
        return email;
    }

    /// <summary>A name without line breaks or other control characters, which have no place in a header.</summary>
    private static string Clean(string value) =>
        new string(value.Where(c => !char.IsControl(c)).ToArray()).Trim();
}
