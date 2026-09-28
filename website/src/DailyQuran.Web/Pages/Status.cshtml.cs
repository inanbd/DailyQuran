using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace DailyQuran.Web.Pages;

[IgnoreAntiforgeryToken]
public sealed class StatusModel : PageModel
{
    public int Code { get; private set; }

    public IActionResult OnGet(int code) => Show(code);

    // A status page is re-executed with the method of the request that failed.
    public IActionResult OnPost(int code) => Show(code);

    private PageResult Show(int code)
    {
        Code = code is >= 400 and <= 599 ? code : 404;
        Response.StatusCode = Code;
        return Page();
    }
}
