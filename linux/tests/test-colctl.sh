#!/bin/sh
# colctl end to end, against a socket of its own: never blocks an agent when Col is not running, relays the event and
# prints the answer Claude Code expects when it is.
set -eu

colctl="$1"
work=$(mktemp -d)
server=""
trap 'kill "$server" 2>/dev/null || true; rm -rf "$work"' EXIT
export COL_SOCKET="$work/col.sock"
export HOME="$work/home"
mkdir -p "$HOME"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

request='{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"}}'

# Col is not running: the hook says nothing, at once, and lets the agent carry on.
start=$(date +%s%N)
out=$(printf '%s' "$request" | "$colctl" hook --agent claude) || fail "hook failed without Col"
elapsed=$(( ($(date +%s%N) - start) / 1000000 ))
[ -z "$out" ] || fail "hook printed '$out' without Col"
[ "$elapsed" -lt 1000 ] || fail "hook took ${elapsed} ms without Col"
[ "$(printf '{"hook_event_name":"AfterTool"}' | "$colctl" hook --agent gemini)" = "{}" ] || fail "gemini's neutral answer"
[ "$(printf '{"hook_event_name":"beforeSubmitPrompt"}' | "$colctl" hook --agent cursor)" = '{"continue":true}' ] || fail "cursor's neutral answer"
printf '' | "$colctl" hook || fail "empty input"
printf '{}' | "$colctl" hook --agent nobody || fail "unknown agent"
if "$colctl" status 2>"$work/err"; then fail "status without Col"; fi
grep -q "Col is not running" "$work/err" || fail "status message"

command -v python3 >/dev/null || { echo "python3 missing: skipping the server half"; exit 0; }

# A stand-in for Col: answers one decision per connection and writes down what it was sent.
cat >"$work/server.py" <<'EOF'
import os, socket, sys
path, decision, log = sys.argv[1], sys.argv[2], sys.argv[3]
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(path)
server.listen(4)
while True:
    client, _ = server.accept()
    data = b""
    while b"\r\n\r\n" not in data:
        data += client.recv(65536)
    head, body = data.split(b"\r\n\r\n", 1)
    length = 0
    for line in head.split(b"\r\n")[1:]:
        name, _, value = line.partition(b":")
        if name.strip().lower() == b"content-length":
            length = int(value)
    while len(body) < length:
        body += client.recv(65536)
    with open(log, "ab") as f:
        f.write(head.split(b"\r\n")[0] + b"\n" + body + b"\n")
    answer = ('{"decision":"%s"}' % decision).encode()
    if head.startswith(b"GET /v1/status"):
        answer = b'{"activities":0,"agents":0,"app":"Col","version":"test"}'
    client.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % len(answer) + answer)
    client.close()
EOF

serve() {
    rm -f "$COL_SOCKET"
    python3 -I "$work/server.py" "$COL_SOCKET" "$1" "$work/log" &
    server=$!
    for _ in $(seq 50); do [ -S "$COL_SOCKET" ] && return; sleep 0.1; done
    fail "the stand-in server did not start"
}

serve allow
out=$(printf '%s' "$request" | "$colctl" hook)
[ "$out" = '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}' ] || fail "allow: $out"
grep -q "POST /v1/agents/events?agent=claude" "$work/log" || fail "the event was not relayed"
grep -q '"tool_input":{"command":"ls"}' "$work/log" || fail "the event was changed on its way"
"$colctl" status | grep -q "Col test is running" || fail "status"
"$colctl" push build --title Build --progress 40% --tint orange
grep -q '"progress":0.4' "$work/log" || fail "push progress"
grep -q '"title":"Build"' "$work/log" || fail "push title"
kill "$server"; wait "$server" 2>/dev/null || true

serve deny
out=$(printf '%s' "$request" | "$colctl" hook --agent codex)
[ "$out" = '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from Col."}}}' ] || fail "deny: $out"
grep -q "agent=codex" "$work/log" || fail "codex's events go out as codex"
kill "$server"; wait "$server" 2>/dev/null || true

serve ask
out=$(printf '%s' "$request" | "$colctl" hook)
[ -z "$out" ] || fail "ask printed '$out'"
# Other events are relayed, and never answered for.
out=$(printf '{"session_id":"s","hook_event_name":"PreToolUse"}' | "$colctl" hook)
[ -z "$out" ] || fail "PreToolUse printed '$out'"
echo "colctl: all good"
