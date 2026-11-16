/* Hook events, what the island says about them, and the answers the hooks print. */

using Col;

HookEvent claude (string json) {
    var raw = JsonText.parse_object (json);
    assert_nonnull (raw);
    var event = CodingAgent.CLAUDE.event_from ((!) raw);
    assert_nonnull (event);
    return (!) event;
}

void test_parse_claude () {
    var event = claude ("""{"session_id":"s1","hook_event_name":"PreToolUse","cwd":"/home/me/projects/col/",
        "tool_name":"Bash","tool_input":{"command":"make test\nmake install","description":"Run the tests"}}""");
    assert_cmpstr (event.session_id, CompareOperator.EQ, "s1");
    assert_cmpstr (event.project (), CompareOperator.EQ, "col");
    assert_true (event.has_agent);
    assert_true (event.agent == CodingAgent.CLAUDE);
    // The agent's description in the summary, never in a request: a request names the command itself.
    assert_cmpstr (event.tool_summary (), CompareOperator.EQ, "Bash · Run the tests");
    assert_cmpstr (event.request_summary (), CompareOperator.EQ, "Bash · make test");
    assert_cmpstr (event.tool_detail (), CompareOperator.EQ, "make test\nmake install");
    assert_null (CodingAgent.CLAUDE.event_from ((!) JsonText.parse_object ("{\"session_id\":\"x\"}")));
}

void test_summaries () {
    var edit = claude ("""{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"/a/b/main.vala"}}""");
    assert_cmpstr (edit.tool_summary (), CompareOperator.EQ, "Edit · main.vala");
    assert_cmpstr (edit.tool_detail (), CompareOperator.EQ, "/a/b/main.vala");
    var fetch = claude ("""{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"WebFetch","tool_input":{"url":"https://lrclib.net/api/get?x=1"}}""");
    assert_cmpstr (fetch.tool_summary (), CompareOperator.EQ, "WebFetch · lrclib.net");
    // A tool of an MCP server shows every argument, sorted, text as it is and the rest as JSON.
    var mcp = claude ("""{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"mcp__db__query","tool_input":{"sql":"DROP TABLE x","limit":5,"opts":{"b":true,"a":null}}}""");
    assert_cmpstr (mcp.tool_detail (), CompareOperator.EQ, "limit: 5\nopts: {\"a\":null,\"b\":true}\nsql: DROP TABLE x");
    var none = claude ("""{"session_id":"s","hook_event_name":"Stop"}""");
    assert_null (none.tool_summary ());
    assert_cmpstr (none.project (), CompareOperator.EQ, "Claude Code");
}

void test_other_agents () {
    var gemini = CodingAgent.GEMINI.event_from ((!) JsonText.parse_object (
        """{"session_id":"g","hook_event_name":"Notification","notification_type":"ToolPermission","message":"Allow?"}"""));
    assert_cmpstr (gemini.event_name, CompareOperator.EQ, "Notification");
    assert_cmpstr (gemini.notification_type, CompareOperator.EQ, "permission_prompt");
    var cursor = CodingAgent.CURSOR.event_from ((!) JsonText.parse_object (
        """{"conversation_id":"c","hook_event_name":"afterShellExecution","command":"ls -la","workspace_roots":["/w/site"]}"""));
    assert_cmpstr (cursor.event_name, CompareOperator.EQ, "PostToolUse");
    assert_cmpstr (cursor.tool_name, CompareOperator.EQ, "Shell");
    assert_cmpstr (cursor.project (), CompareOperator.EQ, "site");
    assert_null (CodingAgent.CURSOR.event_from ((!) JsonText.parse_object ("""{"conversation_id":"c","hook_event_name":"beforeReadFile"}""")));
    assert_cmpstr (CodingAgent.CURSOR.neutral_output ("beforeSubmitPrompt"), CompareOperator.EQ, "{\"continue\":true}");
    assert_cmpstr (CodingAgent.GEMINI.neutral_output ("AfterTool"), CompareOperator.EQ, "{}");
    assert_null (CodingAgent.CLAUDE.neutral_output ("PreToolUse"));
}

void test_decisions () {
    // The answer Claude Code and Codex read from a PermissionRequest hook, as the Mac's colctl writes it.
    var allow = JsonText.parse_object ((!) Decision.ALLOW.hook_output ());
    var specific = JsonText.get_object (allow, "hookSpecificOutput");
    assert_cmpstr (JsonText.get_string (specific, "hookEventName"), CompareOperator.EQ, "PermissionRequest");
    assert_cmpstr (JsonText.get_string (JsonText.get_object (specific, "decision"), "behavior"), CompareOperator.EQ, "allow");
    var deny = JsonText.parse_object ((!) Decision.DENY.hook_output ());
    var decision = JsonText.get_object (JsonText.get_object (deny, "hookSpecificOutput"), "decision");
    assert_cmpstr (JsonText.get_string (decision, "behavior"), CompareOperator.EQ, "deny");
    assert_cmpstr (JsonText.get_string (decision, "message"), CompareOperator.EQ, "Denied from Col.");
    // "ask" prints nothing: the agent asks in the terminal as if Col were not there.
    assert_null (Decision.ASK.hook_output ());
    assert_true (CodingAgent.CLAUDE.answers_permissions () && CodingAgent.CODEX.answers_permissions ());
    assert_false (CodingAgent.GEMINI.answers_permissions ());
}

void test_board () {
    var board = new AgentBoard ();
    board.apply (claude ("""{"session_id":"a","hook_event_name":"UserPromptSubmit","cwd":"/p/one"}"""), 1000);
    board.apply (claude ("""{"session_id":"b","hook_event_name":"PermissionRequest","cwd":"/p/two","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}"""), 2000);
    var ordered = board.ordered ();
    assert_cmpint (ordered.length, CompareOperator.EQ, 2);
    // Waiting for the user comes first.
    assert_cmpstr (ordered[0].id, CompareOperator.EQ, "b");
    assert_true (ordered[0].state == SessionState.WAITING);
    assert_cmpstr (ordered[0].detail, CompareOperator.EQ, "Bash · rm -rf build");
    // A permission prompt notification keeps the request's details.
    board.apply (claude ("""{"session_id":"b","hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission"}"""), 2500);
    assert_cmpstr (board.sessions["b"].detail, CompareOperator.EQ, "Bash · rm -rf build");
    // An event without a folder, as the island makes after an answer, keeps the project.
    board.apply (new HookEvent ("b", "PreToolUse"), 2600);
    assert_cmpstr (board.sessions["b"].project, CompareOperator.EQ, "two");
    assert_true (board.sessions["b"].state == SessionState.WORKING);
    board.apply (claude ("""{"session_id":"b","hook_event_name":"Stop"}"""), 3000);
    assert_true (board.sessions["b"].state == SessionState.DONE);
    assert_false (board.settle (3000 + 5000000));
    assert_true (board.settle (3000 + 6000000));
    assert_true (board.sessions["b"].state == SessionState.IDLE);
    board.apply (claude ("""{"session_id":"a","hook_event_name":"SessionEnd"}"""), 4000);
    assert_null (board.sessions["a"]);
    int active;
    assert_null (board.top (out active));
}

void test_request_detail () {
    var short_command = new RequestDetail ("git push origin main");
    assert_cmpstr (short_command.shown, CompareOperator.EQ, "git push origin main");
    assert_true (short_command.fits_card);
    var hidden = new RequestDetail ("echo hi​ &&  rm\t-rf     /\n");
    assert_cmpstr (hidden.shown, CompareOperator.EQ, "echo hi‹U+200B› &&␣␣rm⇥-rf␣×5/⏎");
    var control = new RequestDetail ("a\x1b[31mb");
    assert_cmpstr (control.shown, CompareOperator.EQ, "a␛[31mb");
    var tall = new RequestDetail ("one\ntwo\nthree\nfour");
    assert_false (tall.fits_card);
    var wide = new RequestDetail (string.nfill (52 * 3, 'x'));
    assert_true (wide.fits_card);
    var wider = new RequestDetail (string.nfill (52 * 3 + 1, 'x'));
    assert_false (wider.fits_card);
    assert_cmpint (RequestDetail.line_count ("日本語", 4), CompareOperator.EQ, 2);
}

void test_activities () {
    ActivityRequest request;
    try {
        request = ActivityRequest.from_json ((!) JsonText.parse_object (
            """{"id":"  build ","title":"Build","progress":1.4,"ttl":0,"tint":"#f80","text":"a text far longer than twenty-four characters"}"""));
    } catch (ActivityError e) {
        error ("%s", e.message);
    }
    assert_cmpstr (request.id, CompareOperator.EQ, "build");
    assert_true (request.has_progress);
    assert_cmpfloat (request.progress, CompareOperator.EQ, 1);
    assert_cmpfloat (request.ttl, CompareOperator.EQ, 1);
    assert_cmpint (request.text.char_count (), CompareOperator.EQ, 24);
    var tint = request.resolved_tint ();
    assert_cmpfloat (tint.red, CompareOperator.EQ, 1);
    assert_true (Math.fabs (tint.green - 0x88 / 255.0) < 0.0001);
    assert_true (request.resolved_priority () == ActivityPriority.STANDARD);
    assert_true (ActivityPriority.parse ("high") == ActivityPriority.ALERT);
    try {
        ActivityRequest.from_json ((!) JsonText.parse_object ("{\"title\":\"no id\"}"));
        assert_not_reached ();
    } catch (ActivityError e) {
    }
    try {
        ActivityRequest.from_json ((!) JsonText.parse_object ("{\"id\":\"%s\"}".printf (string.nfill (65, 'a'))));
        assert_not_reached ();
    } catch (ActivityError e) {
    }
}

void test_http () {
    var request = HttpRequest.parse_head ("POST /v1/agents/events?agent=codex&x=a%20b HTTP/1.1\r\nHost: col\r\nContent-Length: 12");
    assert_nonnull (request);
    assert_cmpstr (request.method, CompareOperator.EQ, "POST");
    assert_cmpstr (request.query["agent"], CompareOperator.EQ, "codex");
    assert_cmpstr (request.query["x"], CompareOperator.EQ, "a b");
    assert_cmpint (request.content_length, CompareOperator.EQ, 12);
    var route = request.route ();
    assert_cmpint (route.length, CompareOperator.EQ, 2);
    assert_cmpstr (route[1], CompareOperator.EQ, "events");
    assert_null (HttpRequest.parse_head ("GET / HTTP/1.1\r\nContent-Length: -1"));
    assert_null (HttpRequest.parse_head ("GET / HTTP/1.1\r\nContent-Length: 99999999999"));
    assert_null (HttpRequest.parse_head ("nonsense"));
    assert_null (HttpRequest.parse_head ("GET /other HTTP/1.1").route ());
    int status;
    string body;
    assert_true (Http.parse_response (Http.response (404, Http.error_body ("not found")), out status, out body));
    assert_cmpint (status, CompareOperator.EQ, 404);
    assert_cmpstr (body, CompareOperator.EQ, "{\"error\":\"not found\"}");
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/agents/parse-claude", test_parse_claude);
    Test.add_func ("/agents/summaries", test_summaries);
    Test.add_func ("/agents/other-agents", test_other_agents);
    Test.add_func ("/agents/decisions", test_decisions);
    Test.add_func ("/agents/board", test_board);
    Test.add_func ("/agents/request-detail", test_request_detail);
    Test.add_func ("/api/activities", test_activities);
    Test.add_func ("/api/http", test_http);
    return Test.run ();
}
