using System.Globalization;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Col.Core;

public sealed record HttpRequest(string Method, string Path, IReadOnlyDictionary<string, string> Query, byte[] Body);

public sealed record HttpResponse(int Status, byte[] Body)
{
    private static readonly JsonWriterOptions Compact = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    public static HttpResponse Json(JsonObject body, int status = 200)
    {
        using var buffer = new MemoryStream();
        using (var writer = new Utf8JsonWriter(buffer, Compact)) body.WriteTo(writer);
        return new HttpResponse(status, buffer.ToArray());
    }

    public static HttpResponse Error(string message, int status) => Json(new JsonObject { ["error"] = message }, status);

    public string Text => Encoding.UTF8.GetString(Body);
}

/// <summary>
/// Plain HTTP/1.1 with JSON bodies, one request per connection, as Col speaks on the Mac over its Unix socket. On
/// Windows it goes over a named pipe that only the user's account can open.
/// </summary>
public static class HttpWire
{
    public const int MaximumBody = 1 << 20;
    private const int MaximumHead = 64 * 1024;
    private static readonly byte[] HeadEnd = "\r\n\r\n"u8.ToArray();

    /// <summary>One request off a stream; null for anything that is not a whole, well-formed request.</summary>
    public static async Task<HttpRequest?> ReadRequestAsync(Stream stream, CancellationToken cancellation)
    {
        var (head, rest) = await ReadHeadAsync(stream, cancellation).ConfigureAwait(false);
        if (head is null) return null;
        var lines = head.Split("\r\n");
        var parts = lines[0].Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2) return null;
        var length = ContentLength(lines);
        if (length is null or > MaximumBody) return null;
        var body = await ReadBodyAsync(stream, rest, length.Value, cancellation).ConfigureAwait(false);
        if (body is null) return null;
        var (path, query) = ParseTarget(parts[1]);
        return new HttpRequest(parts[0].ToUpperInvariant(), path, query, body);
    }

    /// <summary>The status and body of a response; null when the other end said nothing whole.</summary>
    public static async Task<(int Status, byte[] Body)?> ReadResponseAsync(Stream stream, CancellationToken cancellation)
    {
        var (head, rest) = await ReadHeadAsync(stream, cancellation).ConfigureAwait(false);
        if (head is null) return null;
        var lines = head.Split("\r\n");
        var parts = lines[0].Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2 || !int.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out var status)) return null;
        var length = ContentLength(lines);
        if (length is null or > MaximumBody) return null;
        var body = await ReadBodyAsync(stream, rest, length.Value, cancellation).ConfigureAwait(false);
        return body is null ? null : (status, body);
    }

    public static byte[] FormatRequest(string method, string target, byte[]? body)
    {
        body ??= [];
        var head = $"{method} {target} HTTP/1.1\r\nHost: col\r\nContent-Type: application/json\r\nContent-Length: {body.Length}\r\nConnection: close\r\n\r\n";
        return [.. Encoding.ASCII.GetBytes(head), .. body];
    }

    public static byte[] FormatResponse(HttpResponse response)
    {
        var reason = response.Status switch
        {
            200 => "OK",
            400 => "Bad Request",
            404 => "Not Found",
            405 => "Method Not Allowed",
            503 => "Service Unavailable",
            _ => "Status",
        };
        var head = $"HTTP/1.1 {response.Status} {reason}\r\nContent-Type: application/json\r\nContent-Length: {response.Body.Length}\r\nConnection: close\r\n\r\n";
        return [.. Encoding.ASCII.GetBytes(head), .. response.Body];
    }

    /// <summary>The path and the query of a request target, its parts decoded: <c>/v1/activities/build/done?text=Done</c>.</summary>
    public static (string Path, Dictionary<string, string> Query) ParseTarget(string target)
    {
        var query = new Dictionary<string, string>(StringComparer.Ordinal);
        var mark = target.IndexOf('?');
        var path = mark < 0 ? target : target[..mark];
        if (mark >= 0)
        {
            foreach (var pair in target[(mark + 1)..].Split('&', StringSplitOptions.RemoveEmptyEntries))
            {
                var equals = pair.IndexOf('=');
                var name = Decode(equals < 0 ? pair : pair[..equals]);
                var value = equals < 0 ? "" : Decode(pair[(equals + 1)..]);
                query[name] = value;
            }
        }
        return (Decode(path), query);
    }

    private static string Decode(string text)
    {
        try { return Uri.UnescapeDataString(text); }
        catch (UriFormatException) { return text; }
    }

    private static int? ContentLength(string[] lines)
    {
        var length = 0;
        foreach (var line in lines.Skip(1))
        {
            var colon = line.IndexOf(':');
            if (colon <= 0 || !line[..colon].Trim().Equals("content-length", StringComparison.OrdinalIgnoreCase)) continue;
            // A length that is not a count of bytes (negative, or not a number) makes the request a bad one.
            if (!int.TryParse(line[(colon + 1)..].Trim(), NumberStyles.None, CultureInfo.InvariantCulture, out length)) return null;
        }
        return length;
    }

    private static async Task<(string? Head, byte[] Remainder)> ReadHeadAsync(Stream stream, CancellationToken cancellation)
    {
        var data = new List<byte>(1024);
        var chunk = new byte[16 * 1024];
        while (true)
        {
            var index = IndexOf(data, HeadEnd);
            if (index >= 0)
            {
                var head = Encoding.UTF8.GetString(data.GetRange(0, index).ToArray());
                return (head, data.GetRange(index + HeadEnd.Length, data.Count - index - HeadEnd.Length).ToArray());
            }
            if (data.Count > MaximumHead) return (null, []);
            int count;
            try { count = await stream.ReadAsync(chunk, cancellation).ConfigureAwait(false); }
            catch (IOException) { return (null, []); }
            if (count <= 0) return (null, []);
            data.AddRange(chunk.AsSpan(0, count).ToArray());
        }
    }

    private static async Task<byte[]?> ReadBodyAsync(Stream stream, byte[] already, int length, CancellationToken cancellation)
    {
        var body = new byte[length];
        var have = Math.Min(already.Length, length);
        Array.Copy(already, body, have);
        while (have < length)
        {
            int count;
            try { count = await stream.ReadAsync(body.AsMemory(have, length - have), cancellation).ConfigureAwait(false); }
            catch (IOException) { return null; }
            if (count <= 0) return null;
            have += count;
        }
        return body;
    }

    private static int IndexOf(List<byte> data, byte[] pattern)
    {
        for (var i = 0; i <= data.Count - pattern.Length; i++)
        {
            var found = true;
            for (var j = 0; j < pattern.Length; j++)
            {
                if (data[i + j] == pattern[j]) continue;
                found = false;
                break;
            }
            if (found) return i;
        }
        return -1;
    }
}
