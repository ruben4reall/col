# Security

## Reporting a vulnerability

Please open a [private security advisory](https://github.com/ruben4reall/col/security/advisories/new) rather than a
public issue. You will get an answer within a few days.

## What Col touches on your Mac

Everything Col reads, writes or runs, and why.

### Files

| Path | What | When |
|---|---|---|
| `~/Library/Preferences/ch.rubencatalao.islet.plist` | Settings, the shelf's file bookmarks, pinned clipboard text, the songs whose lyrics you moved, chose or hid (their title, artist and LRCLIB number, never the lyrics), the weather's city if you type one, today's count of Pomodoro sessions, and the microphone Col muted until it gives it back | Always |
| `~/Library/Application Support/Col/col.sock` | The local socket scripts and agents talk to: mode 0600 in a 0700 folder, so only your user can connect. It never listens on the network | While Col runs |
| `~/Library/Application Support/Col/Extensions/` | Your extensions, one folder each. A `.col-off` file inside one keeps it off | When you add one, or install one with `colctl extensions install`, which checks its manifest, copies it into a hidden folder Col never reads, marks it off and renames it into place, without running anything of it |
| `~/Library/Application Support/Col/Widgets.json` | The widgets your scripts and devices pushed, so they are still there after a restart: mode 0600 | When a widget is pushed or removed |
| Your login Keychain | The tokens of your AI servers, of the devices paired with Col Connect, and the headers you give widgets read from an address. Never in Col's settings | When you add one |
| `~/Library/Application Support/Col/Scripts/` | The prompter's scripts, one Markdown file each, saved as you type. The first time, the scripts of Souffleur (the prompter's former app) are copied in from `~/Library/Application Support/Souffleur/Scripts/`, which is left as it was | When you use the prompter |
| `~/Library/Preferences/ch.rubencatalao.souffleur.plist` | Read once: the settings made in Souffleur (pace, mode, light, text, shortcuts, the phone remote's pairing) are copied into Col's, except those already set in Col. Whether the remote was on is not copied: it stays off until you turn it on in Col. The file is left as it was | Once, the first time Col runs |
| `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` and the picture it names | Read only: your wallpaper, so the settings previews are drawn on it. A picture in Desktop, Documents, iCloud Drive or on another volume is skipped for the Mac's default wallpaper, so nothing asks for a permission | While a settings pane shows a preview |
| `~/Downloads` | Read only: the names of the files a browser is still writing, to show their progress | While Downloads in progress is on |
| Beside a file on the shelf, or `~/Library/Caches/Col/Shelf/` when its folder cannot be written | What the shelf's tools make: a converted or resized image, a .zip, never over an existing file. A .zip of several files is made from copies in a temporary folder (clones on the same volume), removed at once | When you choose a tool from a file's menu |
| `~/.local/bin/colctl` | A link to the `colctl` command inside the app, or to Homebrew's link to it when Homebrew installed Col, never to a file that cannot run | When you install the command or connect an agent, and on the first launch after an update from Islet if Islet had installed its command. At each launch, a link left leading nowhere or into Islet.app leads to Col again |
| `~/.local/bin/islet` | The command's name before Islet became Col: hooks installed then still call it, so it now links to `colctl` | Only if Islet had installed it: on the first launch after the update, when you connect an agent, and at each launch if it leads nowhere or into Islet.app |
| `~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.gemini/settings.json`, `~/.cursor/hooks.json`, `~/.copilot/hooks/col.json` | Col's hooks, added next to yours; the previous file is kept as `<file>.col-backup`, readable by you only | Read to show which agents are connected; written when you connect one, and disconnecting removes them |
| `~/.copilot/hooks/islet.json` | Where Islet put Copilot's hooks. Set aside as `islet.json.col-backup`, so that VS Code does not call Col twice once Col writes its own file, nor at all once you disconnect Copilot | When you connect or disconnect Copilot, if Islet had connected it |
| `<file>.islet-backup` beside each of these agents' settings, and `~/.copilot/hooks/islet.json.islet-backup` | The copies Islet kept of your settings, which it left readable by the Mac's other accounts: closed to them (readable by you only), and never read, moved or removed | On the first launch of Col, and each time Col edits those settings |
| `~/Library/Application Support/Islet/`, `~/Library/Caches/Islet/` | Where Islet kept the same files: on the first launch of Col they move to Col's folders. `~/Library/Application Support/Islet` is then a link to Col's folder, where `islet.sock`, the socket Islet listened on, is a link to `col.sock`, so scripts written for Islet still reach Col while it runs | The move once, when you update from Islet; the socket's link at each launch |
| `Islet.app`, where the update installed it | Renamed Col.app, and an older Islet.app left beside it or in Applications goes to the Trash. A copy installed with Homebrew keeps its name, so `brew` can still upgrade and remove it: `brew upgrade --cask --greedy col` replaces it with Col.app | Once, when you update from Islet |

Clipboard history (except the text you pin) and the pictures you copy stay in memory and are never written to disk.
Copies that password managers mark as concealed or transient are skipped.

### Processes

- `/usr/bin/perl`, running Col's small media helper (`Contents/Frameworks/libColMediaBridge.dylib`) to read what is
  playing. Since macOS 15.4 only Apple-signed processes may read the now playing information.
- Your extensions' scripts, on the schedule each one declares, with your user's rights. macOS treats each one as a
  program of its own: it never inherits Col's Accessibility, Microphone, Camera or Calendars permissions.
- `/usr/bin/osascript`, when you click an agent's session in the island: a script that selects the Terminal or iTerm2
  tab on the session's terminal (found from the processes above the agent's hook; only a terminal's name ever goes
  in the script) and brings it forward. macOS asks for Automation the first time; refused, Col only brings the app
  forward. VS Code, Cursor, Windsurf and Zed are asked to
  open the session's folder, which brings its window forward; other apps are only brought forward.
- `/usr/bin/git`, when you install an extension from a repository with `colctl extensions install`: a shallow clone,
  without submodules and with hooks turned off, into a temporary folder that is removed afterwards.
- Souffleur, the prompter's former app, when it is open beside Col: Col asks it to quit as it opens (or in the minute
  after, as when both open at login), the way its own Quit command would, so that the two prompters do not both answer
  your shortcuts and your phone. It is never forced to quit, and its app, its files and its login item are left as
  they are.

### Network

- The update check: Sparkle reads `https://getcol.vercel.app/appcast.xml` once a day, and downloads new versions
  from GitHub. Updates are signed with Col's EdDSA key and verified before they are opened. Sparkle's system profile
  is off. You can turn automatic checks off in Settings, General.
- Lyrics, while they are on (Settings, Music and lyrics): the title, the artist, the album and the length of the
  song that plays are sent to [LRCLIB](https://lrclib.net), an open lyrics database, once per song. Answers are kept in
  `~/Library/Caches/Col/Lyrics/`; your own `.lrc` files in `~/Library/Application Support/Col/Lyrics/` are read
  first and never sent anywhere. Lyrics are on in a new install, where the welcome shows the choice; after an update
  from Islet they stay off until you turn them on. When you look for other lyrics for a song (the ⋯ button on the
  lyrics, Not the Right Lyrics?), its title and artist are sent again to LRCLIB's search. The lyrics you choose are
  kept in the same folder; if that copy is gone, they are asked by their LRCLIB number alone (`/api/get/<number>`).
- The AI servers you add in Settings, AI apps, and the Ollama or LM Studio installed on this Mac, which Col asks on
  this Mac only (`localhost`, ports 11434 and 1234): Col asks them every few seconds, only while their page or the
  settings show them, for their models (`/api/tags`, `/api/ps`, `/api/v0/models`, `/v1/models`, `/slots`). A token
  you give is kept in your Keychain and sent only to that server. Col reaches each server at the address you typed,
  over https or plain http: model servers on a home network often speak only http, so App Transport Security allows
  it. Over http, what you send, a token included, crosses your network unencrypted.
- A question you ask from the AI page goes to the server and model you picked, and nowhere else, with the conversation
  so far (the last twenty messages at most). The conversation stays in memory until you start a new one or quit Col;
  it is never written to disk.
- The prompter's phone remote, off until you turn it on in Settings, Prompter: a small web server on your local
  network (port 7575 to 7579) that only answers a phone carrying the pairing code of the QR code you scanned. It
  stops when you turn the remote off. Nothing goes to the internet.
- The weather, off until you turn it on in Settings, Weather and tools: [Open-Meteo](https://open-meteo.com), which
  needs no key and no account, is asked for the forecast at `api.open-meteo.com` with a position rounded to two
  decimals (about a kilometre): the city you typed, or where the Mac is. It is asked at most every 30 minutes, and
  only while the Weather widget or the Lock Screen shows it; nothing is fetched while the island sits closed. Typing
  a city sends that name to `geocoding-api.open-meteo.com` when you search. No cookies, no cache on disk.
- Col Connect, off until you turn it on in Settings, Connect: a small web server on your local network (port 7580 to
  7584), advertised with Bonjour as `_col._tcp`, that only answers the devices you paired, each with its token. It
  stops when you turn it off. See [Col Connect](#col-connect) below.
- The widgets you read from an address (Settings, Connect, Add a Widget from a URL): Col reads each address at the
  interval you chose, only while the widget shows in the island, with the headers you gave, and nothing else. A
  redirect is followed only within the same scheme, host and port, so those headers never reach another host; an
  answer is read up to 1 MB, for 30 seconds at most.
- A widget's button, when you press it: one request to its address, never redirected. The first time that widget's
  button calls it, the island shows the host on its own line and the whole address, and asks. Only http and https,
  without a user part (`name@host`), which could dress one host up as another.
- Nothing else. No account, no telemetry, no analytics, no crash reports.

### Permissions

Each one only if a module you chose needs it: Accessibility (the volume and brightness keys, and measuring the menu
bar), Calendars and Reminders (the agenda), Bluetooth (headphone battery and model), Camera (only while the mirror
is open), Microphone (the prompter's voice modes, while a take runs: the sound is analysed on your Mac and never
recorded), Speech Recognition (the prompter's Voice Follow, on your Mac only), Local Network (the prompter's phone
remote, Col Connect, and the AI servers you add on another machine), Automation of Terminal and iTerm2 (bringing an
agent's tab forward, the first time you click one of its sessions), Downloads folder (only if you turn on Downloads in
progress), System Audio Recording (only if you turn on Bars that follow the sound: while music plays and the bars
show, a Core Audio tap copies the player's sound, or the Mac's when the player's own cannot be told apart, into a
private aggregate device with no other input, so no microphone is ever opened; it is analysed in memory thirty times
a second into the bars' heights, then dropped, never recorded or sent). The colour picker uses the system's own
sampler, which asks for nothing.

Also, only if you turn on what needs it: Location, for the weather where you are, asked when you turn the weather on
without typing a city, and read once per refresh at the accuracy of a town. Caps Lock, when you turn it on, uses the
same Accessibility permission to watch the modifier keys only: never what you type, and nothing is held back. The
batteries of your accessories are read from IOKit's registry, and the text of an image on the shelf is read by
Vision on your Mac.

The microphone's mute (the Live page's button, or ⌃⌥⌘M once you turn it on) sets the default microphone's own mute,
or turns its input volume to zero when it has none, and needs no permission. What Col muted is written in its
settings (`microphoneMuteLedger`: each device's Core Audio UID, how it was muted, the volume it had), so that Col
always gives it back: when you unmute, when you turn the setting off, and when Col quits. If Col stops without
quitting (a crash, a forced quit), the microphone stays muted until Col opens again, which unmutes it first thing.

### Col Connect

What it is for: your phone, a home server, Home Assistant or a build machine on your network pushes activities and
widgets into the island. The threat it is built against: anything else on the same network, a page open in a browser
there, a device you paired and then lost.

- **Off by default.** It listens only while Connect is on, and stops listening when you turn it off.
- **Local network only.** Connections from addresses outside private, link-local and loopback ranges, and outside
  the networks of the Mac's own Wi-Fi and Ethernet interfaces (where a phone may come from a global IPv6 address), are
  closed at once, unless you turn on Accept connections from outside this network.
- **A token for every request.** Each paired device has its own token: 32 random bytes, kept in your Keychain,
  compared in constant time against every token. You can replace a device's token or take it back alone, at once.
  Without a paired device's token, Col answers `401` and nothing else.
- **What a device can reach:** Col's name, version and the number of activities and widgets; pushing, finishing and
  removing activities (in the same namespace as scripts on the Mac, never Col's own); setting and removing widgets.
- **What it cannot reach:** agents' permission requests, which Allow and Deny answer only on the Mac, and every other
  route of the local API (the agents' events, the list of activities, the extensions); your settings, files,
  clipboard, music or anything else. Widget buttons a device pushes are only called when you press them, and the
  first time only after the island showed you the address.
- **Limits.** A request's head is 8 KB at most and its body 64 KB, refused before it is read; chunked bodies are
  refused; a request has five seconds to arrive; sixteen connections at once, four waiting from one address; each
  address 60 requests at once then 20 a second; after ten wrong tokens, an address waits thirty seconds for each new
  try. Programs and devices together keep 32 activities and 32 widgets at most: a new one past that is refused.
- **Plain HTTP.** Requests are not encrypted: someone who can read your network's traffic can read a token. Use
  Connect on networks you trust, and take back a token you think was seen.
- **Browsers.** A web page cannot send the token it does not know, and Col sends no CORS headers, so a page's request
  with a token is refused by the browser before it is sent. The page the pairing code opens is served without a token
  and holds none: the token stays in its address's fragment, on the phone.
- **Bonjour** says to the network that a Mac runs Col Connect, and on which port, while it is on.

### Login item

When you choose Open at Login, Col registers itself with `SMAppService`. It shows in System Settings, General,
Login Items. After an update from Islet, the login item is registered again for Col.app.

### Private macOS APIs

MediaRemote (now playing), DisplayServices (brightness), undocumented `IOBluetoothDevice` properties (headphone
battery and model), `CABackdropLayer`, `CAFilter` and the `glassBackground` filter of Liquid Glass (the Liquid and Transparent glass of the
open island), SkyLight (the Lock
Screen and its lyrics, off by default) and TCC (whether System Audio Recording is allowed, and asking for it, only for
Bars that follow the sound, off by default). Each is looked up at run time: if a macOS update
removes one, its feature turns off and nothing crashes. The [README](README.md#private-macos-apis) says why each is
needed.

CoreBrightness's `KeyboardBrightnessClient` (the keyboard backlight's level, for its keys) is looked up the same way.

## Col for Windows and Linux

The Windows and Linux editions keep the same promises: no account, no telemetry, scripts and agents reach Col only
through a channel that your account alone can open (a named pipe on Windows, a Unix socket in `$XDG_RUNTIME_DIR` on
Linux), and Allow and Deny for your agents never travel over the network. They use the network only for the lyrics
of what plays, while lyrics are on (LRCLIB), and on Linux for the covers players give as web addresses. What each one
touches is listed in [windows/README.md](windows/README.md#privacy) and [linux/README.md](linux/README.md#privacy).
The Windows builds are not code-signed yet: SmartScreen asks once before the first launch.
