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

It can print a [widget](widgets.md) under `widget`, for the island's Widgets place, alone or beside the activity:

```json
{"widget": {"title": "Homebrew", "value": 3, "unit": "outdated", "symbol": "mug.fill", "tint": "orange"}}
```

Printing nothing clears the extension's activity and its widget. The command can also call `colctl push` or
`colctl widget set` itself, for things that change between runs. `COL_EXTENSION` holds the folder name (so does
`ISLET_EXTENSION`, for extensions written for Islet), and `PATH` includes Homebrew and `~/.local/bin`.

Extensions are scripts you install yourself and run with your permissions, like any script. Read one before you add
it. They do not inherit Col's own privacy permissions (Accessibility, Microphone, Camera, Calendars): macOS treats
each one as a program of its own. Turn them on and off in Settings, Developers.

## Installing

Put the folder in the extensions folder (Settings, Developers, Open the Extensions Folder), or let `colctl` check it
and copy it there:

```sh
colctl extensions install examples/extensions/countdown           # a folder on this Mac
colctl extensions install https://github.com/you/col-weather.git  # a repository (https or ssh)
colctl extensions install https://github.com/you/col-extras.git --path ci --name my-ci
colctl extensions list
colctl extensions remove countdown                                # to the Trash
```

`install` reads `extension.json` and refuses a folder whose manifest has no name, no command or no interval. It runs
nothing of the extension: a repository is cloned without its hooks or submodules into a temporary folder, removed
afterwards whatever happens. The extension is copied into a hidden folder Col never reads, then put in place in one
step, never over an extension already there. It arrives turned off, with a `.col-off` file inside it, so you can read
it first, then turn it on in Settings, Developers, which removes that file. `--on` turns it on at once, for an
extension you wrote or already read. `colctl` never writes Col's settings, and a running Col picks the change up at
once.

## Catalog

The examples in [`examples/extensions`](../examples/extensions), each with a README:

| Extension | Shows | Needs | Every |
|---|---|---|---|
| [Countdown](../examples/extensions/countdown) | The days left until a date, as a widget | macOS | hour |
| [Homebrew Outdated](../examples/extensions/homebrew-outdated) | How many packages have a newer version, the first three named | Homebrew | hour |
| [Docker Containers](../examples/extensions/docker-containers) | How many containers run, the first three named | Docker, OrbStack or Colima | minute |
| [Website Status](../examples/extensions/website-status) | Whether a site answers and how fast; an alert beside the camera while it is down | macOS (`curl`) | minute |
| [GitHub Actions](../examples/extensions/github-actions) | The last workflow run of a repository, beside the camera while it runs | GitHub CLI | minute |
| [Uptime](../examples/extensions/uptime) | How long the Mac has been up, for five seconds every hour | macOS | hour |

```sh
colctl extensions install examples/extensions/homebrew-outdated --on
```

Add the Widgets place to a page (Settings, Pages, or Settings, Connect, Add a Widgets Page) to see the widgets.
