# Col for Windows (preview)

A Dynamic Island for Windows: a black capsule floating at the top centre of your screen that comes alive when
something happens. The song playing and its synced lyrics, the volume, the charger, a timer, and your coding agents,
with Allow and Deny when Claude Code or Codex asks for permission.

This is the first Windows edition of [Col](../README.md), released with Col 3.0.0 as a **preview**. It is a native app
(C# and WPF on .NET 8), with no web view inside.

## What it does

- **The island.** Windows has no notch, so the island floats 8 pixels below the top edge, rounded on all four corners.
  By default it shows only when something happens; rest the pointer on the top edge of the screen, right above where
  it sleeps, and it comes out. A short rest makes it peek, a click or a longer rest opens it. It opens with a slight
  overshoot and closes without one, and nothing moves while it rests. Clicks around the capsule, and anywhere on the
  top edge, go to the windows below: a maximised browser keeps its tabs. It follows each monitor's scale (per-monitor
  DPI) and steps aside under full-screen apps unless an agent needs you.
- **Now playing.** Whatever shows in Windows' media controls (Spotify, a browser, Media Player): the title, the
  artist, the cover, play, pause, next, previous and a scrubber. Closed, the island shows the cover and a small
  equalizer.
- **Synced lyrics.** The words of the song beside the player, the line being sung lit; click a line to go there.
  Optionally, the current line in the closed island.
- **Coding agents.** Claude Code and Codex sessions show in the island with the agent's logo, the project and the tool
  at work. A permission request opens the island with the whole command, every character visible, and Allow and Deny;
  the answer goes back to the agent exactly as it expects. A command too long to check in the island is left to the
  terminal. Other agents and scripts report with `colctl agent`.
- **System displays.** A volume gauge when the volume changes (Windows' own flyout still shows), the charger plugged
  in or out with the battery's charge, and a warning when the battery runs low.
- **Tools.** A timer that counts down in the closed island, keep awake, and a clipboard history kept in memory only,
  with pins.
- **Settings.** In the style of Windows 11 (Mica, your accent colour, light or dark as Windows is): General, Music and
  lyrics, Agents, About. Open them from the tray icon, or from the gear in the open island.
- **English and French**, following the display language of Windows.

## Install

1. Download `Col-3.0.0-windows-setup.exe` from the [latest release](https://github.com/ruben4reall/col/releases/latest).
2. Run it. It installs for your account only, in `%LOCALAPPDATA%\Programs\Col`, without administrator rights: a Start
   menu entry, `col://` links, `colctl` on your PATH, and, if you leave the box ticked, Col at sign-in.

The setup looks for the [.NET 8 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/8.0) on your PC. When it
is there, it installs the small `Col.exe`, which uses it; when it is not, the full one, with .NET inside. Run it with
`/SELFCONTAINED=yes` to install the full one anyway. If you install the small one and later remove the .NET 8 Desktop
Runtime, install Col again.

Or take a zip, unzip it anywhere and run `Col.exe`: everything is in that folder.

- `Col-3.0.0-windows-x64.zip` (or `-arm64.zip`): .NET inside, nothing else to install.
- `Col-3.0.0-windows-x64-small.zip` (or `-arm64-small.zip`): for a PC that has the .NET 8 Desktop Runtime, from
  Microsoft's link above (x64 or Arm64, as your PC).

Windows 10 version 2004 or later, or Windows 11; x64 or Arm64.

| | Size |
|---|---|
| `Col-3.0.0-windows-setup.exe` (x64 and Arm64, small and full, in one) | about 115 MB |
| `Col-3.0.0-windows-x64.zip`, .NET inside | 85 MB |
| `Col-3.0.0-windows-x64-small.zip` | about 8 MB |
| `Col.exe` with .NET inside, unpacked | 222 MB |
| `Col.exe` small, unpacked | 27 MB |
| `colctl.exe`, compiled ahead of time to native code (in every download) | 2.4 MB |

The full `Col.exe` carries .NET and WPF uncompressed, on purpose: Windows maps them from the file instead of
unpacking them into Col's own memory, which keeps Col light while it runs. Most of the small one is the part of .NET
that reaches Windows' own APIs (media controls, accent colour).

## Light on your PC

Measured by the workflow on GitHub's Windows Server 2025 machines, one minute after the last event, nothing playing:

| | Col for Windows |
|---|---|
| Private memory at rest | about 50 to 60 MB |
| Working set at rest | about 130 to 150 MB |
| Processor at rest | 0.000 to 0.013 % |
| Processor while music plays (the equalizer dances, at 24 frames a second) | about 0.5 % |
| A hook, from the agent's call to its answer | about 30 ms; when Col is not running, it gives up after 300 ms (0.4 to 0.6 s with the command's own start) |

The island is one window that never moves or resizes: springs reshape the capsule inside it, frame by frame while
they move, and nothing runs once they rest. Media, volume, battery, clipboard and full-screen apps are followed
through Windows' own notifications, never by asking again and again; the timer and the line of lyrics wait for
exactly the moment they change.

### The binaries are not signed yet

Col for Windows has no code-signing certificate yet, so Windows SmartScreen may stop the installer or `Col.exe` the
first time with "Windows protected your PC". Choose **More info**, then **Run anyway**. Every file is built from this
repository by the [windows workflow](../.github/workflows/windows.yml) on GitHub's own machines; the workflow's logs
show how.

### Uninstall

Settings, Apps, Installed apps, Col, Uninstall. The uninstaller first disconnects your agents (so no hook calls a
command that is gone), then removes Col, its `col://` links, its PATH entry, its line at sign-in and
`%LOCALAPPDATA%\Col`.

## Coding agents

In Settings, Agents, click Connect beside Claude Code or Codex, or from a terminal:

```powershell
colctl hooks install --agent all      # every agent found on this PC: claude, codex
colctl hooks status
colctl hooks uninstall --agent codex
```

| Agent | Where Col adds its hooks | In the island |
|---|---|---|
| Claude Code | `%USERPROFILE%\.claude\settings.json` | Sessions, and permission requests with Allow and Deny |
| Codex | `%USERPROFILE%\.codex\hooks.json` | Sessions, and permission requests with Allow and Deny |

Col adds its hooks beside yours, keeps a copy of the file it edits (`settings.json.col-backup`) and leaves the rest
untouched. A file that is not valid JSON is left alone. The hook calls `colctl.exe` by its full path, in a form that
Git Bash and cmd read the same way. Codex runs a new hook once you trust it with `/hooks`.

When Col is not running, a hook gives up after 300 milliseconds and the agent carries on as if Col were not there.
A permission request waits up to 90 seconds for your answer in the island, then goes back to the terminal.

## colctl and the local API

The same commands and the same JSON as on the Mac ([docs/api.md](../docs/api.md)):

```powershell
colctl push build --title "Build" --symbol hammer.fill --tint orange --progress 40%
colctl done build
colctl remove build
colctl list
colctl status
colctl agent Aider working --message "Refactoring"
```

Col listens on a named pipe, `\\.\pipe\col-<your account's SID>`, speaking plain HTTP/1.1 with JSON bodies: the same
routes as the Mac's socket (`GET /v1/status`, `GET` and `POST /v1/activities`, `POST /v1/activities/<id>/done`,
`DELETE /v1/activities/<id>`, `POST /v1/agents/events?agent=claude|codex`). The pipe's access list names your
account alone and refuses anyone coming over the network, and `colctl` checks that the pipe it reaches belongs to
your account. One route is Windows' own: `POST /v1/open?url=col://...`, which a second copy of Col uses to hand a
link to the one running. `COL_PIPE` gives a development build a pipe of its own.

Windows has no SF Symbols: an activity's `--symbol` shows as Col's own glyph for the few it knows (checkmark, timer,
speaker, music, cup, bolt, battery, hammer) and as a dot of its colour otherwise.

Links work as on the Mac: `col://push?id=tea&title=Tea&ttl=240`, `col://done?id=tea`, `col://remove?id=tea`,
`col://settings?pane=agents`.

## Privacy

- No account, no telemetry, no analytics, no crash reports.
- The network is used for one thing: [LRCLIB](https://lrclib.net), an open lyrics database, while synced lyrics are
  on (Settings, Music and lyrics; on by default). Only the title, the artist, the album and the length of the song
  that plays are sent, with a User-Agent that names Col. Answers are kept in `%LOCALAPPDATA%\Col\lyrics`, so a song
  is asked for once; when LRCLIB asks to slow down, Col waits as long as it says.
- The clipboard history lives in memory only, pins included, and skips copies that password managers mark as
  private. Nothing of it is written to disk.
- Scripts and agents reach Col through a pipe only your account can open.
- To know when the pointer rests on the top edge, Col watches the pointer's position with a low-level mouse hook, as
  pointer utilities do: no window lies on the top edge, so it cannot take your clicks there. The hook reads where the
  pointer is and whether a button is held, on this PC only, and keeps nothing.
- Col keeps its settings in `%LOCALAPPDATA%\Col\settings.json` and a short log of errors (never what plays, what you
  copy or what an agent runs) in `%LOCALAPPDATA%\Col\col.log`.

## Build from source

You need the [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0).

```powershell
git clone https://github.com/ruben4reall/col.git
cd col
dotnet test windows/tests/Col.Tests                          # the rules: geometry, springs, agents, lyrics, API
dotnet run --project windows/src/Col                         # the island
dotnet run --project windows/src/Col -- --demo lyrics        # a demo state, with made-up data
dotnet publish windows/src/Col -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish        # .NET inside
dotnet publish windows/src/Col -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true -o small   # small
dotnet publish windows/src/colctl -c Release -r win-x64 -o publish   # native code, needs Visual Studio's C++ tools
```

The rules (`Col.Core`) target plain .NET 8, so their tests also run on a Mac or Linux; the app and colctl build
there too with `-p:EnableWindowsTargeting=true` (set in `Directory.Build.props`), but only run on Windows.

Demo states, for screenshots that come out the same every time: `--demo collapsed`, `peek`, `music`, `lyrics`,
`agent-permission`, `agents`, `live`, `volume`, `battery`, `timer`, `tools`, `settings` (with `--page general`,
`music`, `agents` or `about`). `--lang fr` shows French whatever the language of Windows, `--theme dark` or `light`
the settings in that mode. The workflow runs each one
on a Windows machine and keeps the screenshots, then drives the real app with `colctl` and a permission request
answered through UI Automation (`windows/tools/e2e.ps1`).

| Folder | What lives there |
|---|---|
| `src/Col.Core` | Geometry, springs, the rules that open and close the island, activities, agents, lyrics, the API. No Windows API, fully tested |
| `src/Col` | The WPF app: the island window, its pages, the settings, the tray icon, media, volume, clipboard, the pipe |
| `src/colctl` | The command and the agents' hook |
| `tests/Col.Tests` | xUnit tests of `Col.Core` |
| `installer` | The Inno Setup script |
| `tools` | The strings (`strings.py` writes the .resx files), screenshots and end-to-end checks |

To change a word, edit `tools/strings.py` and run it: it writes `Resources/Strings.resx` and `Strings.fr.resx`.

## Known limits of the preview

- Not signed (see above), and no automatic updates yet: download new versions from the releases.
- Claude Code and Codex only; the Mac's other agents (Gemini CLI, Cursor, Copilot) are not connected from the
  settings yet, though the API understands their events.
- No headphone battery, brightness, file shelf, agenda, prompter, AI apps page or extensions yet.
- The volume gauge shows beside Windows' own flyout, which Col does not hide.
- The island stays under the Start menu, Search and the notification centre: Windows keeps them above every app.
- Players that do not publish to Windows' media controls do not show.
- Tested on Windows Server 2025 machines (GitHub's) at 100 % scale and without a sound card or a battery, so the
  volume and battery displays were checked with demo data only. The Arm64 build is made but not run.
- The island comes out when the pointer rests on the top row of pixels right above it; resting a moment on a
  maximised browser's tabs there, before clicking, can bring it out. The click itself always goes to the browser.
- The full `Col.exe` is large (see above): the price of a self-contained .NET app that stays light in memory. The
  small one needs the .NET 8 Desktop Runtime.

## Credits

The logos of Claude Code and Codex come from [LobeHub Icons](https://github.com/lobehub/lobe-icons) (MIT) and belong
to their owners. Licence: MIT, see [LICENSE](../LICENSE).
