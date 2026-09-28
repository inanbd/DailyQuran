using System.Globalization;
using System.Security.Cryptography;
using Microsoft.AspNetCore.DataProtection;

namespace DailyQuran.Web.Contact;

public enum GuardVerdict
{
    /// <summary>Looks like a person: send it.</summary>
    Person,

    /// <summary>Looks automated: thank the sender and drop it.</summary>
    Automated,

    /// <summary>The form was opened too long ago to vouch for: ask them to send again.</summary>
    Expired,
}

/// <summary>
/// Spam protection without a third-party captcha, which would send every
/// visitor's details to someone else. A hidden field people never see but form
/// fillers complete, and a signed timestamp: a person takes more than a couple
/// of seconds to write a message. The rate limiter in Program.cs does the rest.
/// </summary>
public sealed class ContactFormGuard(IDataProtectionProvider protection, TimeProvider clock)
{
    public static readonly TimeSpan MinimumTime = TimeSpan.FromSeconds(3);
    public static readonly TimeSpan MaximumAge = TimeSpan.FromHours(12);

    private readonly IDataProtector _protector = protection.CreateProtector("DailyQuran.Contact.FormOpened");

    /// <summary>A token recording when the form was shown, which only this site can read or forge.</summary>
    public string IssueToken() =>
        _protector.Protect(clock.GetUtcNow().ToUnixTimeMilliseconds().ToString(CultureInfo.InvariantCulture));

    public GuardVerdict Check(string? token, string? honeypot)
    {
        if (!string.IsNullOrEmpty(honeypot) || string.IsNullOrEmpty(token))
        {
            return GuardVerdict.Automated;
        }

        long opened;
        try
        {
            opened = long.Parse(_protector.Unprotect(token), CultureInfo.InvariantCulture);
        }
        catch (Exception ex) when (ex is CryptographicException or FormatException)
        {
            // Most often a form left open across a restart that changed keys.
            return GuardVerdict.Expired;
        }

        TimeSpan age = clock.GetUtcNow() - DateTimeOffset.FromUnixTimeMilliseconds(opened);
        if (age < MinimumTime)
        {
            return GuardVerdict.Automated;
        }
        return age > MaximumAge ? GuardVerdict.Expired : GuardVerdict.Person;
    }
}
