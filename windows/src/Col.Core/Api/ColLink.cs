using System.Globalization;

namespace Col.Core;

/// <summary>
/// A <c>col://</c> link, as on the Mac: <c>col://push?id=tea&amp;title=Tea&amp;ttl=240</c>, <c>col://done?id=tea</c>,
/// <c>col://remove?id=tea</c>, <c>col://settings?pane=agents</c>.
/// </summary>
public sealed record ColLink(string Action, IReadOnlyDictionary<string, string> Query)
{
    public static ColLink? Parse(string? url)
    {
        if (url is null || !url.StartsWith("col://", StringComparison.OrdinalIgnoreCase)) return null;
        var rest = url["col://".Length..];
        var mark = rest.IndexOf('?');
        var action = (mark < 0 ? rest : rest[..mark]).Trim('/').ToLowerInvariant();
        var (_, query) = HttpWire.ParseTarget(mark < 0 ? "/" : "/" + rest[mark..]);
        return new ColLink(action, query);
    }

    /// <summary>The activity a push link describes; null without an id, or with one the API would refuse.</summary>
    public ActivityRequest? ToRequest()
    {
        if (!Query.TryGetValue("id", out var id) || string.IsNullOrWhiteSpace(id)) return null;
        double? Number(string key) => Query.TryGetValue(key, out var text) &&
            double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) ? value : null;
        var request = new ActivityRequest(id)
        {
            Title = Query.GetValueOrDefault("title"), Subtitle = Query.GetValueOrDefault("subtitle"),
            Symbol = Query.GetValueOrDefault("symbol"), Tint = Query.GetValueOrDefault("tint"),
            Progress = Number("progress"), Text = Query.GetValueOrDefault("text"),
            Priority = Query.GetValueOrDefault("priority"), Ttl = Number("ttl"),
        };
        try { return request.Validated(); }
        catch (ActivityRequest.InvalidException) { return null; }
    }
}
