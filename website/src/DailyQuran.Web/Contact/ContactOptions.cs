using MailKit.Security;

namespace DailyQuran.Web.Contact;

public enum ContactDelivery
{
    /// <summary>Send through an SMTP server.</summary>
    Smtp,

    /// <summary>Write each message as an .eml file to a folder — for trying the form locally.</summary>
    PickupDirectory,
}

/// <summary>The <c>Contact</c> section of appsettings.json.</summary>
public sealed class ContactOptions
{
    public const string Section = "Contact";

    /// <summary>Where messages are delivered: an address, or several separated by commas.</summary>
    public string Recipient { get; set; } = "";

    public ContactDelivery Delivery { get; set; } = ContactDelivery.Smtp;

    public SmtpOptions Smtp { get; set; } = new();

    /// <summary>For <see cref="ContactDelivery.PickupDirectory"/>; relative to the content root.</summary>
    public string PickupDirectory { get; set; } = "App_Data/outbox";

    public bool IsConfigured =>
        Recipient.Length > 0 && Delivery switch
        {
            ContactDelivery.PickupDirectory => true,
            _ => Smtp.Host.Length > 0 && Smtp.SenderAddress.Length > 0,
        };
}

public sealed class SmtpOptions
{
    public string Host { get; set; } = "";

    public int Port { get; set; } = 587;

    /// <summary><c>StartTls</c> for port 587, <c>SslOnConnect</c> for 465, <c>Auto</c> to let MailKit decide.</summary>
    public SecureSocketOptions Security { get; set; } = SecureSocketOptions.StartTls;

    public string Username { get; set; } = "";

    public string Password { get; set; } = "";

    /// <summary>The address messages are sent from. Defaults to <see cref="Username"/>, which most providers require.</summary>
    public string FromAddress { get; set; } = "";

    public string FromName { get; set; } = "Daily Quran website";

    public string SenderAddress => FromAddress.Length > 0 ? FromAddress : Username;
}
