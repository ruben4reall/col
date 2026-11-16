using System.Text;
using System.Text.Json.Nodes;
using Col.Core;
using Microsoft.Extensions.Time.Testing;

namespace Col.Tests;

public class HttpWireTests
{
    [Fact]
    public async Task ARequestWrittenByColctlIsReadBackWhole()
    {
        var body = """{"id":"build","title":"Build"}"""u8.ToArray();
        var bytes = HttpWire.FormatRequest("POST", "/v1/activities/build/done?text=All%20good", body);
        var request = await HttpWire.ReadRequestAsync(new MemoryStream(bytes), CancellationToken.None);
        Assert.NotNull(request);
        Assert.Equal("POST", request.Method);
        Assert.Equal("/v1/activities/build/done", request.Path);
        Assert.Equal("All good", request.Query["text"]);
        Assert.Equal(body, request.Body);
    }

    [Fact]
    public async Task ABodyThatArrivesInPiecesIsWaitedFor()
    {
        var body = Encoding.UTF8.GetBytes(new string('x', 40_000));
        var stream = new TrickleStream(HttpWire.FormatRequest("POST", "/v1/activities", body), 700);
        var request = await HttpWire.ReadRequestAsync(stream, CancellationToken.None);
        Assert.Equal(40_000, request!.Body.Length);
    }

    [Fact]
    public async Task MalformedRequestsAreRefused()
    {
        async Task<HttpRequest?> Read(string text) => await HttpWire.ReadRequestAsync(new MemoryStream(Encoding.ASCII.GetBytes(text)), CancellationToken.None);
        Assert.Null(await Read("GET\r\n\r\n"));
        Assert.Null(await Read("POST /v1/activities HTTP/1.1\r\nContent-Length: -4\r\n\r\n"));
        Assert.Null(await Read("POST /v1/activities HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n"));
        // Fewer bytes than announced: the other end hung up.
        Assert.Null(await Read("POST /v1/activities HTTP/1.1\r\nContent-Length: 10\r\n\r\n{}"));
        Assert.Null(await Read("GET /v1/status HTTP/1.1\r\n"));
    }

    [Fact]
    public async Task AResponseIsReadAsColctlReadsIt()
    {
        var bytes = HttpWire.FormatResponse(HttpResponse.Json(new JsonObject { ["decision"] = "allow" }));
        Assert.StartsWith("HTTP/1.1 200 OK\r\n", Encoding.ASCII.GetString(bytes));
        var response = await HttpWire.ReadResponseAsync(new MemoryStream(bytes), CancellationToken.None);
        Assert.Equal(200, response!.Value.Status);
        Assert.Equal("""{"decision":"allow"}""", Encoding.UTF8.GetString(response.Value.Body));
    }

    /// <summary>A stream that hands out its bytes a few at a time, as a pipe can.</summary>
    private sealed class TrickleStream(byte[] data, int piece) : MemoryStream(data)
    {
        public override int Read(byte[] buffer, int offset, int count) => base.Read(buffer, offset, Math.Min(count, piece));

        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default) =>
            base.ReadAsync(buffer[..Math.Min(buffer.Length, piece)], cancellationToken);
    }
}

public class ControlApiTests
{
    private readonly FakeTimeProvider _time = new(DateTimeOffset.Parse("2026-11-16T10:00:00Z"));
    private readonly CustomActivities _custom = new();
    private readonly AgentCenter _agents;
    private readonly ControlApi _api;

    public ControlApiTests()
    {
        _agents = new AgentCenter(_time);
        _api = new ControlApi(_custom, _agents, "3.0.0", _time);
    }

    private Task<HttpResponse> Send(string method, string target, string? body = null)
    {
        var (path, query) = HttpWire.ParseTarget(target);
        return _api.HandleAsync(new HttpRequest(method, path, query, body is null ? [] : Encoding.UTF8.GetBytes(body)));
    }

    private static JsonObject Json(HttpResponse response) => (JsonObject)JsonNode.Parse(response.Body)!;

    [Fact]
    public async Task StatusSaysWhoAnswers()
    {
        var status = Json(await Send("GET", "/v1/status"));
        Assert.Equal("Col", (string?)status["app"]);
        Assert.Equal("3.0.0", (string?)status["version"]);
        Assert.Equal(0, (int)status["activities"]!);
        Assert.Equal(0, (int)status["agents"]!);
    }

    [Fact]
    public async Task ActivitiesArePushedListedFinishedAndRemoved()
    {
        var pushed = await Send("POST", "/v1/activities", """{"id":"build","title":"Build","progress":4,"tint":"orange","ttl":0}""");
        Assert.Equal(200, pushed.Status);
        Assert.Equal("build", (string?)Json(pushed)["id"]);
        var entry = _custom.Entries.Single();
        Assert.Equal(1, entry.Request.Progress);
        Assert.Equal(_time.GetUtcNow().AddSeconds(1), entry.Expires);

        var list = (JsonArray)Json(await Send("GET", "/v1/activities"))["activities"]!;
        Assert.Equal("Build", (string?)list[0]!["title"]);
        Assert.False((bool)list[0]!["finished"]!);

        Assert.Equal(200, (await Send("POST", "/v1/activities/build/done?text=Done")).Status);
        Assert.True(_custom.Entries.Single().Finished);
        Assert.Equal("Done", _custom.Entries.Single().Request.Text);
        Assert.Equal(404, (await Send("POST", "/v1/activities/nothing/done")).Status);

        Assert.Equal(200, (await Send("DELETE", "/v1/activities/build")).Status);
        Assert.Empty(_custom.Entries);
    }

    [Fact]
    public async Task AnActivityNeedsAnId()
    {
        Assert.Equal(400, (await Send("POST", "/v1/activities", """{"title":"No id"}""")).Status);
        Assert.Equal(400, (await Send("POST", "/v1/activities", """{"id":"   "}""")).Status);
        Assert.Equal(400, (await Send("POST", "/v1/activities", "{\"id\":\"" + new string('x', 65) + "\"}")).Status);
        Assert.Equal(400, (await Send("POST", "/v1/activities", "not json")).Status);
        var error = Json(await Send("POST", "/v1/activities", "{}"));
        Assert.Equal("expected an activity with an id", (string?)error["error"]);
    }

    [Fact]
    public async Task UnknownRoutesAreNotFound()
    {
        Assert.Equal(404, (await Send("GET", "/v2/status")).Status);
        Assert.Equal(404, (await Send("PUT", "/v1/activities")).Status);
        Assert.Equal(404, (await Send("GET", "/")).Status);
    }

    [Fact]
    public async Task AHookEventIsAnsweredAndAPermissionWaitsForTheIsland()
    {
        var plain = await Send("POST", "/v1/agents/events?agent=claude", """{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}""");
        Assert.Equal("ask", (string?)Json(plain)["decision"]);
        Assert.Equal(1, (int)Json(await Send("GET", "/v1/status"))["agents"]!);

        var waiting = Send("POST", "/v1/agents/events", """{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"git push"}}""");
        Assert.False(waiting.IsCompleted);
        _agents.Decide(_agents.Pending.Single().Id, Decision.Allow);
        Assert.Equal("allow", (string?)Json(await waiting)["decision"]);

        Assert.Equal(400, (await Send("POST", "/v1/agents/events?agent=nobody", "{}")).Status);
        Assert.Equal(400, (await Send("POST", "/v1/agents/events", "[]")).Status);
        // An event Col does not follow is acknowledged.
        Assert.Equal("ask", (string?)Json(await Send("POST", "/v1/agents/events?agent=gemini", """{"session_id":"g","hook_event_name":"BeforeModel"}"""))["decision"]);
    }

    [Fact]
    public async Task ASecondCopyHandsItsLinkToTheOneRunning()
    {
        string? opened = null;
        _api.OpenLink = url => { opened = url; return true; };
        Assert.Equal(200, (await Send("POST", "/v1/open?url=col%3A%2F%2Fsettings%3Fpane%3Dagents")).Status);
        Assert.Equal("col://settings?pane=agents", opened);
        Assert.Equal(400, (await Send("POST", "/v1/open?url=https%3A%2F%2Fexample.com")).Status);
    }
}

public class ColLinkTests
{
    [Fact]
    public void LinksPushFinishAndRemoveLikeTheApi()
    {
        var push = ColLink.Parse("col://push?id=tea&title=Tea%20time&progress=0.5&ttl=240")!;
        Assert.Equal("push", push.Action);
        var request = push.ToRequest()!;
        Assert.Equal("tea", request.Id);
        Assert.Equal("Tea time", request.Title);
        Assert.Equal(0.5, request.Progress);
        Assert.Equal(240, request.Ttl);
        Assert.Equal("settings", ColLink.Parse("col://settings?pane=agents")!.Action);
        Assert.Equal("agents", ColLink.Parse("col://settings?pane=agents")!.Query["pane"]);
        Assert.Equal("done", ColLink.Parse("COL://done?id=tea")!.Action);
        Assert.Null(ColLink.Parse("https://example.com"));
        Assert.Null(ColLink.Parse("col://push?title=No%20id")!.ToRequest());
    }
}
