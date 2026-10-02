# The Col API

Col listens on a Unix domain socket:

```
~/Library/Application Support/Col/col.sock
```

The socket file is readable only by your user account, so only programs running as you can reach it. Web pages
cannot: browsers do not open Unix sockets. It speaks plain HTTP/1.1 with JSON bodies.

## The `colctl` command

```
colctl push <id> [--title T] [--subtitle S] [--symbol SF_SYMBOL] [--tint COLOR]
                [--progress 0..1 | N%] [--text T] [--priority ambient|standard|alert] [--ttl SECONDS]
colctl done <id> [--text T]
colctl remove <id>
colctl list
colctl status
colctl agent <name> <working|waiting|done|idle|end> [--message M] [--session S]
colctl hook [--agent AGENT]      # the hook itself, reads the agent's event on stdin
colctl hooks install [--agent claude|codex|gemini|cursor|copilot|all] [--settings PATH]
colctl hooks uninstall [--agent AGENT] [--settings PATH]
colctl hooks status
```

Colours: `white`, `green`, `orange`, `red`, `blue`, `purple`, `yellow`, `pink`, `teal`, `gray`, or `#RRGGBB`.

## What an activity shows

Beside the camera, the left wing shows the symbol in the tint colour. The right wing shows a ring when there is a
progress, otherwise the text. In the open island, the Live page lists every activity with its title, subtitle and
progress bar.

When several activities want the notch, the highest priority wins, then the most recent:
`alert` > `standard` > `ambient`. Col's own brief displays (volume, charger) come first for a second or two.

## Endpoints

| Method and path | Body | Answer |
|---|---|---|
| `GET /v1/status` | | `{"app": "Col", "version": "0.1.0", "activities": 1, "agents": 0}` |
| `GET /v1/activities` | | `{"activities": [{"id": "build", "title": "Build", "progress": 0.4}]}` |
| `POST /v1/activities` | an activity | `{"id": "build"}` |
| `POST /v1/activities/<id>/done?text=Done` | | `{"id": "build"}` |
| `DELETE /v1/activities/<id>` | | `{"id": "build"}` |
| `POST /v1/agents/events?agent=codex` | a hook event, as the agent wrote it | `{"decision": "allow"}`, `"deny"` or `"ask"` |

An activity:

```json
{
  "id": "build",
  "title": "Build",
  "subtitle": "12 of 40 files",
  "symbol": "hammer.fill",
  "tint": "orange",
  "progress": 0.3,
  "text": "30%",
  "priority": "standard",
  "ttl": 60
}
```

Only `id` is required: 64 characters at most. `progress` is clamped to 0 to 1; `ttl` to one second to one day.

With curl:

```sh
curl --unix-socket "$HOME/Library/Application Support/Col/col.sock" \
  -X POST http://col/v1/activities \
  -d '{"id":"deploy","title":"Deploy","progress":0.6,"tint":"teal"}'
```

## Links

```
col://push?id=tea&title=Tea&symbol=cup.and.saucer.fill&ttl=240
col://done?id=tea
col://remove?id=tea
col://settings?pane=developers   # general, appearance, pages, activities, music, prompter, aiApps,
                                   # permissions, shortcuts, developers, about
col://welcome                    # the welcome tour
```

## The prompter

The prompter answers its own links, from a script, a Shortcut or a browser:

| Link | Does |
|---|---|
| `col://prompter/prompt?text=…&title=…` | Rolls this text out of the notch (without `text`, the script selected in the library) |
| `col://prompter/toggle` | Plays or pauses; opens the selected script when nothing rolls |
| `col://prompter/play`, `pause`, `stop` | Plays, pauses, closes the prompter |
| `col://prompter/faster`, `slower`, `restart` | Ten words a minute more or less; back to the start |
| `col://prompter/clipboard` | Rolls the text on the clipboard |
| `col://prompter/library` | Opens the Scripts window |

The links of Souffleur, the prompter's former app, still work: `souffleur://toggle` is `col://prompter/toggle`.
Shortcuts has actions for the same things: Prompt Text, Prompt the Selected Script, Play or Pause the Prompter and
Close the Prompter.

## Agents

`POST /v1/agents/events` takes the JSON an agent writes on a hook's stdin, unchanged. `?agent=` says which agent
wrote it: `claude` (the default), `codex`, `gemini`, `cursor` or `copilot`. Col translates each agent's events into
the same states:

| State | Claude Code, Codex | Gemini CLI | Cursor | GitHub Copilot in VS Code |
|---|---|---|---|---|
| Started | `SessionStart` | `SessionStart` | `sessionStart` | `SessionStart` |
| Working | `UserPromptSubmit`, `PreToolUse`, `PostToolUse` | `BeforeAgent`, `BeforeTool`, `AfterTool` | `beforeSubmitPrompt`, `postToolUse`, `afterShellExecution`, `afterFileEdit` | `UserPromptSubmit`, `PreToolUse`, `PostToolUse` |
| Waiting for you | `PermissionRequest`, `Notification` | `Notification` (`ToolPermission`) | | |
| Done | `Stop` | `AfterAgent` | `stop` | `Stop` |
| Ended | `SessionEnd` | `SessionEnd` | `sessionEnd` | |

For a Claude Code or Codex `PermissionRequest`, the request waits until the user answers from the island, for up to
90 seconds. The answer is `allow`, `deny`, or `ask`, which means "let the agent ask in the terminal". `colctl hook`
turns it into the hook output both agents read. For Gemini CLI and Cursor, `colctl hook` always answers the neutral
output they expect (`{}`, or `{"continue": true}` before a Cursor prompt), so their own behaviour never changes. Copilot
only reports: VS Code applies each session's own permission mode, and sends no event when a chat ends, so a Copilot
session leaves the island once its Done has shown.

### Other agents

Agents and scripts without hooks report their state with `colctl agent`:

```sh
colctl agent Aider working --message "Refactoring the parser"
colctl agent Aider waiting --message "Approve the plan"
colctl agent Aider done
```

