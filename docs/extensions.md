# Extensions

An extension is a folder in `~/Library/Application Support/Col/Extensions` with an `extension.json`:

```json
{
  "name": "GitHub Actions",
  "description": "The last workflow run of my app",
  "command": "./status.sh",
  "interval": 60
}
```

Col runs `command` with `/bin/sh` in the extension's folder, when it starts and then every `interval` seconds
(10 at least). A run that takes more than ten seconds is stopped.

The command prints an activity as JSON, with the fields of [`colctl push`](api.md) and no id:

```json
{"title": "CI", "symbol": "checkmark.seal.fill", "tint": "green", "text": "Passed", "ttl": 60}
```

Printing nothing clears the extension's activity. The command can also call `colctl push` itself, for activities that
change between runs. `COL_EXTENSION` holds the folder name (so does `ISLET_EXTENSION`, for extensions written for
Islet), and `PATH` includes Homebrew and `~/.local/bin`.

Extensions are scripts you install yourself and run with your permissions, like any script. Read one before you add
it. They do not inherit Col's own privacy permissions (Accessibility, Microphone, Camera, Calendars): macOS treats
each one as a program of its own. Turn them on and off in Col's settings.

Examples: [`examples/extensions`](../examples/extensions).
