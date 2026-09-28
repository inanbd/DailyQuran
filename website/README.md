# Daily Quran — the website

The app's public site: what Daily Quran does, with screenshots and download
links, the whole Qur'an to read in every edition the app ships, a contact form
that emails you, and the privacy policy. No accounts, no analytics, and no
requests to anyone else — fonts and images are served from the site itself.

ASP.NET Core 10, Razor Pages. The Qur'an is read into memory at startup from
the app's own `assets/data`, so every page after that is served without
touching the disk.

| Page | What it is |
|---|---|
| `/` | Home: the app in brief, the ayah for today, screenshots, download badges |
| `/features` | Every feature, with screenshots, and the latest release notes from `CHANGELOG.md` |
| `/quran` | The surah index: search by name or number, or go straight to `2:255` |
| `/quran/{surah}` · `/quran/{surah}/{ayah}` | The reader: any edition, word by word, text size, typeface, light and dark |
| `/contact` | The contact form, which sends you an email |
| `/privacy` | The site's own privacy notes, then `PRIVACY.md` |
| `/sources` | Every edition's translator, source and licence |
| `/sitemap.xml` · `/robots.txt` · `/healthz` | For search engines and hosts |

## Running it

```bash
cd website
dotnet run --project src/DailyQuran.Web
```

Then open <http://localhost:5242>. In Development the contact form doesn't
send anything: each message is written to `src/DailyQuran.Web/App_Data/outbox`
as an `.eml` file, which any mail program opens.

```bash
dotnet test        # 59 tests: the data, the reader, every page, the contact form
```

## Configuration

Everything is in `src/DailyQuran.Web/appsettings.json`. Each setting can also
be given as an environment variable, with `__` for each level —
`Site__Stores__AppStore`, `Contact__Smtp__Password` — which is where secrets
belong in production.

### Download links

```json
"Site": {
  "BaseUrl": "https://dailyquran.example",
  "Publisher": "i9Tech",
  "Stores": {
    "GooglePlay": "https://play.google.com/apps/internaltest/4701262937540230372",
    "GooglePlayInternalTesting": true,
    "AppStore": "",
    "Apk": "https://github.com/inanbd/DailyQuran/releases/latest"
  },
  "SourceCodeUrl": "https://github.com/inanbd/DailyQuran"
}
```

- **`GooglePlay`, `AppStore`** — the links behind the store badges. Leave one
  empty and its badge shows **Coming soon** instead of linking nowhere; the App
  Store starts that way. When the iPhone app is live, paste its
  `https://apps.apple.com/app/id…` link here.
- **`GooglePlayInternalTesting`** — while the app is in internal testing, only
  testers you have added can install it. On, a note above the Google Play badge
  reads *"The Android app is in internal testing on Google Play. Contact the
  developer to get access."*, linking to the contact form with **Access to the
  Android app** already chosen; the form then asks for the Google account on
  the visitor's phone, which is the address you add to the testers list.

**When the app goes public**, change two settings — no new build:

```json
"GooglePlay": "https://play.google.com/store/apps/details?id=com.i9tech.qurandaily",
"GooglePlayInternalTesting": false,
```

The site reads its `Site` settings afresh for every page, so an edit to
`appsettings.json` on the server shows on the next page load, without even a
restart. In a container, where `appsettings.json` is inside the image, set
`Site__Stores__GooglePlay` and `Site__Stores__GooglePlayInternalTesting=false`
as environment variables and restart it instead.
- **`Apk`** — offered in small print under the badges, for Android without
  Google Play. Empty hides it.
- **`BaseUrl`** — the site's public address, for canonical links, the sitemap
  and link previews. Empty uses whatever address each request arrived on.
- **`SourceCodeUrl`** — the GitHub repository; its issue tracker is offered on
  the contact page and in the footer. Empty hides both.

### The contact form

Messages are sent through any SMTP server. They come *from* your own address,
with the visitor as **Reply-To**, so replying in your mail program answers them.

```json
"Contact": {
  "Recipient": "you@example.com",
  "Delivery": "Smtp",
  "Smtp": {
    "Host": "smtp.gmail.com",
    "Port": 587,
    "Security": "StartTls",
    "Username": "you@gmail.com",
    "Password": "",
    "FromAddress": "",
    "FromName": "Daily Quran website"
  }
}
```

| Provider | Host | Port | Security | Password |
|---|---|---|---|---|
| Gmail / Google Workspace | `smtp.gmail.com` | 587 | `StartTls` | An [app password](https://myaccount.google.com/apppasswords), not your own |
| Outlook / Microsoft 365 | `smtp.office365.com` | 587 | `StartTls` | Requires SMTP AUTH enabled for the mailbox |
| Zoho | `smtp.zoho.com` | 465 | `SslOnConnect` | An app-specific password |
| SendGrid | `smtp.sendgrid.net` | 587 | `StartTls` | Username `apikey`, password the API key |

- **`Recipient`** takes one address or several, comma-separated.
- **`FromAddress`** defaults to `Username`, which most providers insist on.
- Until `Recipient` and `Smtp:Host` are set, the form tells visitors messages
  can't be sent just now, and the site logs a warning at startup.

Spam is kept out without a third-party captcha, which would hand every
visitor's details to someone else: a hidden field only bots fill in, a signed
timestamp (nobody writes a message in under three seconds), and at most five
messages per visitor in fifteen minutes. The site keeps no copy of any message.

### Keys

The contact form's tokens are signed with ASP.NET Core data-protection keys.
Set `DataProtection:KeysPath` to a folder that survives a redeploy — the
Docker image uses `/keys`, so mount a volume there — or a form open during a
restart will ask to be sent again.

## Deploying

### Docker (any host)

Build from the **repository root**, so the image can take the app's data:

```bash
docker build -f website/Dockerfile -t dailyquran-web .
docker run -p 8080:8080 -v dailyquran-keys:/keys \
  -e Site__BaseUrl=https://dailyquran.example \
  -e Contact__Recipient=you@example.com \
  -e Contact__Smtp__Host=smtp.gmail.com \
  -e Contact__Smtp__Username=you@gmail.com \
  -e Contact__Smtp__Password=your-app-password \
  dailyquran-web
```

That runs on Azure Container Apps or App Service, Render, Fly.io, Railway, or
a VPS behind nginx or Caddy. The image listens on 8080 and trusts the
`X-Forwarded-*` headers of the proxy in front of it, which is how these hosts
tell it the visitor's scheme and address.

### Without Docker

```bash
dotnet publish website/src/DailyQuran.Web -c Release -o out
```

`out/` is self-contained apart from the .NET 10 runtime: run
`dotnet DailyQuran.Web.dll`, or point IIS at it — the `web.config` is already
there.

## Where the content comes from

The site reads the repository rather than keeping copies:

- **`assets/data/`** — the catalog, surah index, word index and every verified
  edition, copied in at build time. The development fixture is left out.
  Import a new edition for the app and the site has it on its next build.
- **`PRIVACY.md`** and **`CHANGELOG.md`** — rendered on `/privacy`, and as
  "What's new" on `/features`.

The same rule the app holds to applies here: Qur'an text is never generated,
paraphrased or corrected. Every Arabic line on the site, the basmala included,
comes verbatim from the data files.

Two things are copies, and need refreshing by hand:

- **Screenshots** — `wwwroot/img/screens/` holds the Play Store screenshots
  from `fastlane/metadata/android/en-US/images/phoneScreenshots/`. Copy them
  across again when they change; `PhoneShot.cs` describes each for screen
  readers.
- **Fonts** — self-hosted from Google Fonts, all under the SIL Open Font
  License. `tools/fetch-fonts.ps1 -OutDir src/DailyQuran.Web/wwwroot/fonts`
  downloads them again and rewrites `fonts.css`.

The store badges are Google's and Apple's official artwork, used as their
guidelines allow for linking to an app's listing.

## Security

- A strict Content Security Policy: scripts, styles, fonts and images from
  this origin only, with one inline script (the theme, applied before first
  paint) allowed by a per-request nonce.
- Antiforgery tokens on the contact form, and its page is never compressed —
  a secret token beside text the visitor typed is what BREACH exploits.
- One cookie, `dq_reader`, remembering the reader's edition and word-by-word
  choice; HttpOnly, SameSite=Lax. Text size, typeface, theme and the last place
  read stay in the browser's own storage.
