using System.Globalization;
using System.Resources;
using System.Windows.Markup;

namespace Col.Localization;

/// <summary>Col's words, in the language of Windows: English, or French (Resources\Strings.fr.resx).</summary>
internal static class L
{
    private static readonly ResourceManager Manager = new("Col.Resources.Strings", typeof(L).Assembly);

    public static string Get(string key) => Manager.GetString(key, CultureInfo.CurrentUICulture) ?? key;

    public static string Format(string key, params object[] arguments) =>
        string.Format(CultureInfo.CurrentCulture, Get(key), arguments);
}

/// <summary>A string of Col's in XAML: <c>Text="{l:Loc Settings_Title}"</c>.</summary>
[MarkupExtensionReturnType(typeof(string))]
public sealed class LocExtension(string key) : MarkupExtension
{
    public string Key { get; set; } = key;

    public LocExtension() : this("") { }

    public override object ProvideValue(IServiceProvider serviceProvider) => L.Get(Key);
}
