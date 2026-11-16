using System.Globalization;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Col.Core;

public enum LyricsAnswerKind
{
    Found,
    Instrumental,
    NotFound,
    /// <summary>The database could not be reached, or asked to wait: try again later.</summary>
    Unavailable,
}

public sealed record LyricsAnswer(LyricsAnswerKind Kind, Lyrics? Lyrics = null)
{
    public static readonly LyricsAnswer Instrumental = new(LyricsAnswerKind.Instrumental);
    public static readonly LyricsAnswer NotFound = new(LyricsAnswerKind.NotFound);
    public static readonly LyricsAnswer Unavailable = new(LyricsAnswerKind.Unavailable);
}

/// <summary>
/// Finds the lyrics of a track in LRCLIB, an open database of lyrics that needs no account. Only the title, the
/// artist, the album and the length of the track are sent. Answers are kept on disk (misses for a week), so a track is
/// looked up once. When LRCLIB asks to slow down (429), nothing is asked until the time it gives has passed.
/// </summary>
public sealed class LrclibClient : IDisposable
{
    private static readonly Uri Base = new("https://lrclib.net/api/");
    private static readonly TimeSpan MissLifetime = TimeSpan.FromDays(7);

    private readonly HttpClient _http;
    private readonly string _cacheFolder;
    private readonly TimeProvider _time;
    private DateTimeOffset? _quietUntil;
    private readonly object _lock = new();

    /// <param name="cacheFolder">Where answers are kept: %LOCALAPPDATA%\Col\lyrics in the app.</param>
    /// <param name="handler">The network, replaced in tests.</param>
    public LrclibClient(string cacheFolder, string version, HttpMessageHandler? handler = null, TimeProvider? time = null)
    {
        _cacheFolder = cacheFolder;
        _time = time ?? TimeProvider.System;
        _http = handler is null ? new HttpClient() : new HttpClient(handler);
        _http.Timeout = TimeSpan.FromSeconds(8);
        _http.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent", UserAgent(version));
    }

    /// <summary>LRCLIB asks every client to say who it is.</summary>
    public static string UserAgent(string version) => $"Col {version} for Windows (https://github.com/ruben4reall/col)";

    public async Task<LyricsAnswer> LookUpAsync(LyricsQuery query, CancellationToken cancellation = default)
    {
        var key = query.CacheKey;
        if (Cached(key) is { } cached) return cached;
        lock (_lock)
        {
            if (_quietUntil is { } until && until > _time.GetUtcNow()) return LyricsAnswer.Unavailable;
        }
        var (answer, record) = await FetchAsync(query, cancellation).ConfigureAwait(false);
        if (answer.Kind != LyricsAnswerKind.Unavailable) Store(record, key);
        return answer;
    }

    /// <summary>The address of the exact lookup: title, artist, album and length.</summary>
    public static Uri ExactUri(LyricsQuery query)
    {
        var parameters = new List<(string, string)> { ("track_name", query.CleanTitle), ("artist_name", query.MainArtist) };
        if (query.Album.Length > 0) parameters.Add(("album_name", query.Album));
        if (query.Duration > 0) parameters.Add(("duration", ((int)Math.Round(query.Duration, MidpointRounding.AwayFromZero)).ToString(CultureInfo.InvariantCulture)));
        return new Uri(Base, "get?" + Encode(parameters));
    }

    /// <summary>The address of the search that tolerates a different album or spelling.</summary>
    public static Uri SearchUri(LyricsQuery query) =>
        new(Base, "search?" + Encode([("track_name", query.CleanTitle), ("artist_name", query.MainArtist)]));

    private static string Encode(IEnumerable<(string Name, string Value)> parameters) =>
        string.Join("&", parameters.Select(p => $"{p.Name}={Uri.EscapeDataString(p.Value)}"));

    private async Task<(LyricsAnswer, JsonObject?)> FetchAsync(LyricsQuery query, CancellationToken cancellation)
    {
        // The exact track first, then a search.
        var exact = await RequestAsync(ExactUri(query), cancellation).ConfigureAwait(false);
        if (exact.Failed) return (LyricsAnswer.Unavailable, null);
        if (exact.Node is JsonObject record) return (AnswerFrom(record), record);
        var search = await RequestAsync(SearchUri(query), cancellation).ConfigureAwait(false);
        if (search.Failed) return (LyricsAnswer.Unavailable, null);
        if (search.Node is not JsonArray records) return (LyricsAnswer.NotFound, null);
        var candidates = records.OfType<JsonObject>().Where(r => query.Matches(Number(r, "duration"))).ToList();
        // Synced lyrics beat plain ones.
        var best = candidates.FirstOrDefault(r => !string.IsNullOrEmpty(Text(r, "syncedLyrics"))) ?? candidates.FirstOrDefault();
        return best is null ? (LyricsAnswer.NotFound, null) : (AnswerFrom(best), best);
    }

    private static LyricsAnswer AnswerFrom(JsonObject record) =>
        Answer(Text(record, "syncedLyrics"), Text(record, "plainLyrics"), Bool(record, "instrumental"));

    private static LyricsAnswer Answer(string? synced, string? plain, bool instrumental)
    {
        if (instrumental) return LyricsAnswer.Instrumental;
        if (synced is not null && Lyrics.Parse(synced) is { } timed) return new LyricsAnswer(LyricsAnswerKind.Found, timed);
        if (plain is not null && Lyrics.Plain(plain) is { } text) return new LyricsAnswer(LyricsAnswerKind.Found, text);
        return LyricsAnswer.NotFound;
    }

    private readonly record struct Reply(bool Failed, JsonNode? Node);

    /// <summary>A node for a 200, nothing for a 404, a failure for anything that should be tried again later.</summary>
    private async Task<Reply> RequestAsync(Uri uri, CancellationToken cancellation)
    {
        try
        {
            using var response = await _http.GetAsync(uri, cancellation).ConfigureAwait(false);
            switch (response.StatusCode)
            {
                case HttpStatusCode.OK:
                    var body = await response.Content.ReadAsByteArrayAsync(cancellation).ConfigureAwait(false);
                    try { return new Reply(false, JsonNode.Parse(body)); }
                    catch (JsonException) { return new Reply(false, null); }
                case HttpStatusCode.NotFound:
                    return new Reply(false, null);
                case HttpStatusCode.TooManyRequests:
                    var wait = response.Headers.RetryAfter?.Delta?.TotalSeconds
                        ?? (response.Headers.RetryAfter?.Date is { } date ? (date - _time.GetUtcNow()).TotalSeconds : 60);
                    lock (_lock) _quietUntil = _time.GetUtcNow().AddSeconds(Math.Clamp(wait, 5, 3600));
                    return new Reply(true, null);
                default:
                    return new Reply(true, null);
            }
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException or IOException)
        {
            return new Reply(true, null);
        }
    }

    // The cache: one small JSON file per track, named after a digest of its key, holding LRCLIB's record as it came.

    private string FileFor(string key)
    {
        var digest = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(key))).ToLowerInvariant();
        return Path.Combine(_cacheFolder, digest + ".json");
    }

    private LyricsAnswer? Cached(string key)
    {
        try
        {
            var file = FileFor(key);
            if (!File.Exists(file)) return null;
            if (JsonNode.Parse(File.ReadAllBytes(file)) is not JsonObject entry) return null;
            var answer = Answer(Text(entry, "synced"), Text(entry, "plain"), Bool(entry, "instrumental"));
            if (answer.Kind != LyricsAnswerKind.NotFound) return answer;
            // A miss is asked again after a week: someone may have added the lyrics since.
            var fetched = Text(entry, "fetched") is { } stamp &&
                DateTimeOffset.TryParse(stamp, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var when) ? when : DateTimeOffset.MinValue;
            return _time.GetUtcNow() - fetched < MissLifetime ? LyricsAnswer.NotFound : null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException)
        {
            return null;
        }
    }

    /// <summary>Keeps a record as LRCLIB gave it, or a miss when there is none.</summary>
    private void Store(JsonObject? record, string key)
    {
        try
        {
            Directory.CreateDirectory(_cacheFolder);
            var entry = new JsonObject
            {
                ["synced"] = record is null ? null : Text(record, "syncedLyrics"),
                ["plain"] = record is null ? null : Text(record, "plainLyrics"),
                ["instrumental"] = record is not null && Bool(record, "instrumental"),
                ["fetched"] = _time.GetUtcNow().ToString("O", CultureInfo.InvariantCulture),
            };
            var file = FileFor(key);
            var partial = file + ".partial";
            File.WriteAllText(partial, entry.ToJsonString());
            File.Move(partial, file, overwrite: true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // Not kept: asked again next time.
        }
    }

    /// <summary>Forgets every answer kept on disk.</summary>
    public void ClearCache()
    {
        try
        {
            if (!Directory.Exists(_cacheFolder)) return;
            foreach (var file in Directory.EnumerateFiles(_cacheFolder, "*.json")) File.Delete(file);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
        }
    }

    private static string? Text(JsonObject json, string key) =>
        json[key] is JsonValue value && value.TryGetValue(out string? text) ? text : null;

    private static bool Bool(JsonObject json, string key) =>
        json[key] is JsonValue value && value.TryGetValue(out bool flag) && flag;

    private static double? Number(JsonObject json, string key) =>
        json[key] is JsonValue value && value.TryGetValue(out double number) ? number : null;

    public void Dispose() => _http.Dispose();
}
