using MailKit.Net.Smtp;
using Microsoft.Extensions.Options;
using MimeKit;

namespace DailyQuran.Web.Contact;

public interface IContactMailer
{
    Task SendAsync(ContactMessage message, CancellationToken cancellationToken);
}

/// <summary>Delivers messages through the SMTP server in <see cref="ContactOptions.Smtp"/>.</summary>
public sealed class SmtpContactMailer(IOptions<ContactOptions> options) : IContactMailer
{
    public async Task SendAsync(ContactMessage message, CancellationToken cancellationToken)
    {
        ContactOptions settings = options.Value;
        MimeMessage email = ContactEmail.Compose(message, settings);

        using var client = new SmtpClient { Timeout = 20_000 };
        await client.ConnectAsync(settings.Smtp.Host, settings.Smtp.Port, settings.Smtp.Security, cancellationToken);
        if (settings.Smtp.Username.Length > 0)
        {
            await client.AuthenticateAsync(settings.Smtp.Username, settings.Smtp.Password, cancellationToken);
        }
        await client.SendAsync(email, cancellationToken);
        await client.DisconnectAsync(quit: true, cancellationToken);
    }
}

/// <summary>
/// Writes each message to a folder as an .eml file, which any mail program
/// opens. For running the site locally without an SMTP server.
/// </summary>
public sealed class PickupDirectoryContactMailer(
    IOptions<ContactOptions> options,
    IHostEnvironment environment,
    ILogger<PickupDirectoryContactMailer> logger) : IContactMailer
{
    public async Task SendAsync(ContactMessage message, CancellationToken cancellationToken)
    {
        ContactOptions settings = options.Value;
        string folder = Path.IsPathRooted(settings.PickupDirectory)
            ? settings.PickupDirectory
            : Path.Combine(environment.ContentRootPath, settings.PickupDirectory);
        Directory.CreateDirectory(folder);

        string path = Path.Combine(folder, $"{message.SentAt:yyyyMMdd-HHmmss}-{Guid.NewGuid():N}.eml");
        await ContactEmail.Compose(message, settings).WriteToAsync(path, cancellationToken);
        logger.LogInformation("Contact form: wrote the message to {Path}.", path);
    }
}
