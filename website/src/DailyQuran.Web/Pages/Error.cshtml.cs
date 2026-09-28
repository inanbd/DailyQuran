using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace DailyQuran.Web.Pages;

[IgnoreAntiforgeryToken]
[ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
public sealed class ErrorModel : PageModel
{
    public void OnGet() => Response.StatusCode = StatusCodes.Status500InternalServerError;

    public void OnPost() => OnGet();
}
