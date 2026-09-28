using System.ComponentModel.DataAnnotations;
using DailyQuran.Web.Contact;
using DailyQuran.Web.Site;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.Extensions.Options;
using MimeKit;

namespace DailyQuran.Web.Pages;

public sealed class ContactModel(
    IContactMailer mailer,
    ContactFormGuard guard,
    IOptions<ContactOptions> options,
    IOptionsSnapshot<SiteOptions> site,
    TimeProvider clock,
    ILogger<ContactModel> logger) : PageModel
{
    [BindProperty]
    public ContactInput Input { get; set; } = new();

    /// <summary>The honeypot: hidden from people, irresistible to form-filling bots.</summary>
    [BindProperty]
    public string? Website { get; set; }

    [BindProperty]
    public string? FormToken { get; set; }

    public bool Sent { get; private set; }

    public bool Busy { get; private set; }

    public string? Problem { get; private set; }

    public bool IsAvailable => options.Value.IsConfigured;

    /// <summary>Whether the app is in internal testing, so visitors may ask to be added as testers.</summary>
    public bool AppInTesting => site.Value.Stores.GooglePlayInternalTesting;

    public IReadOnlyList<ContactTopic> Topics => ContactTopic.Offered(AppInTesting);

    public void OnGet(bool sent = false, bool busy = false, string? topic = null)
    {
        Sent = sent;
        Busy = busy;
        FormToken = guard.IssueToken();
        if (ContactTopic.Find(topic) is { } chosen && Topics.Contains(chosen))
        {
            Input.Topic = chosen.Key;
        }
    }

    public async Task<IActionResult> OnPostAsync(CancellationToken cancellationToken)
    {
        switch (guard.Check(FormToken, Website))
        {
            case GuardVerdict.Automated:
                // Thank it like anyone else, so it learns nothing.
                logger.LogInformation("Contact form: set aside a submission that looked automated.");
                return RedirectToPage(new { sent = true });

            case GuardVerdict.Expired:
                FormToken = guard.IssueToken();
                Problem = "This page was open for a long while, so for your security the form has expired. Your message is still here — please press Send again.";
                return Page();
        }

        if (!ModelState.IsValid)
        {
            return Page();
        }

        if (!IsAvailable)
        {
            Problem = "Sorry — messages can’t be sent from this page just now. Please try again later.";
            return Page();
        }

        var message = new ContactMessage(
            Input.Name.Trim(),
            Input.Email.Trim(),
            ContactTopic.Find(Input.Topic)!,
            Input.Message,
            clock.GetUtcNow());

        try
        {
            await mailer.SendAsync(message, cancellationToken);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogError(ex, "Contact form: the message could not be sent.");
            Problem = "Sorry — your message couldn’t be sent just now. Please try again in a little while.";
            return Page();
        }

        return RedirectToPage(new { sent = true });
    }
}

// Every check is on a property, so a visitor sees all their mistakes at once:
// object-level validation only runs once every property has passed.
public sealed class ContactInput
{
    [Required(ErrorMessage = "Please tell us your name.")]
    [StringLength(100, ErrorMessage = "Please keep your name under 100 characters.")]
    public string Name { get; set; } = "";

    [Required(ErrorMessage = "Please give an email address we can reply to.")]
    [StringLength(254, ErrorMessage = "That email address is too long.")]
    [Mailbox(ErrorMessage = "That doesn’t look like an email address.")]
    public string Email { get; set; } = "";

    [KnownTopic(ErrorMessage = "Please choose what your message is about.")]
    public string Topic { get; set; } = ContactTopic.All[0].Key;

    [Required(ErrorMessage = "Please write your message.")]
    [StringLength(5000, MinimumLength = 10, ErrorMessage = "Please write at least a few words, and no more than 5,000 characters.")]
    public string Message { get; set; } = "";
}

/// <summary>A single, bare address that MimeKit can send to — not a list, and not "Name &lt;address&gt;".</summary>
public sealed class MailboxAttribute : ValidationAttribute
{
    public override bool IsValid(object? value)
    {
        string email = (value as string)?.Trim() ?? "";
        return email.Length == 0
            || (email.Contains('@') && MailboxAddress.TryParse(email, out MailboxAddress? parsed) && parsed.Address == email);
    }
}

public sealed class KnownTopicAttribute : ValidationAttribute
{
    public override bool IsValid(object? value) => ContactTopic.Find(value as string) is not null;
}
