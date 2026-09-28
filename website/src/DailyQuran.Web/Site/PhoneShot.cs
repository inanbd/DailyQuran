namespace DailyQuran.Web.Site;

/// <summary>One of the app's Play Store screenshots, shown in a phone frame.</summary>
public sealed record PhoneShot(string File, string Alt, string CssClass = "", bool Eager = false)
{
    public static readonly PhoneShot Read = new("1_read.png", "The reading screen: an ayah from Al-Baqarah in Arabic, with its Bengali and English translations beneath, and today’s goal below.");
    public static readonly PhoneShot Planner = new("2_planner.png", "The Qur’an Planner: a plan to finish in one month, on track, with 31 days left, and the choices of one month, one year or a date you pick.");
    public static readonly PhoneShot Progress = new("3_progress.png", "Your Progress: a one-day streak, 20 minutes read today, the days of the week, and the plan’s goal for today.");
    public static readonly PhoneShot Reminders = new("4_reminders.png", "Notification settings: a daily reminder, how often it comes, and two reminder times.");
    public static readonly PhoneShot Library = new("5_library.png", "The translations: Arabic only, Spanish, French, Russian, Urdu, Bengali and English.");

    public PhoneShot With(string cssClass, bool eager = false) => this with { CssClass = cssClass, Eager = eager };
}
