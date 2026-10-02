# Security

## Reporting a vulnerability

Please open a [private security advisory](https://github.com/ruben4reall/col/security/advisories/new) rather than a
public issue. You will get an answer within a few days.

## What Col touches on your Mac

Everything Col reads, writes or runs, and why.

### Files

| Path | What | When |
|---|---|---|
| `~/Library/Preferences/ch.rubencatalao.islet.plist` | Settings, the shelf's file bookmarks, pinned clipboard text | Always |
| `~/Library/Application Support/Col/col.sock` | The local socket scripts and agents talk to: mode 0600 in a 0700 folder, so only your user can connect. It never listens on the network | While Col runs |
| `~/Library/Application Support/Col/Extensions/` | Your extensions, one folder each | When you add one |
| `~/Library/Application Support/Col/Scripts/` | The prompter's scripts, one Markdown file each, saved as you type. The first time, the scripts of Souffleur (the prompter's former app) are copied in from `~/Library/Application Support/Souffleur/Scripts/`, which is left as it was | When you use the prompter |
| `~/Library/Preferences/ch.rubencatalao.souffleur.plist` | Read once: the settings made in Souffleur (pace, mode, light, text, shortcuts, the phone remote's pairing) are copied into Col's, except those already set in Col. The file is left as it was | Once, the first time Col runs |
| `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` and the picture it names | Read only: your wallpaper, so the settings previews are drawn on it. A picture in Desktop, Documents, iCloud Drive or on another volume is skipped for the Mac's default wallpaper, so nothing asks for a permission | While a settings pane shows a preview |
| `~/Downloads` | Read only: the names of the files a browser is still writing, to show their progress | While Downloads in progress is on |
| `~/.local/bin/colctl` | A link to the `colctl` command inside the app | When you install the command |
| `~/.local/bin/islet` | The command's name before Islet became Col: hooks installed then still call it, so it now links to `colctl` | Only if Islet had installed it |
| `~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.gemini/settings.json`, `~/.cursor/hooks.json`, `~/.copilot/hooks/col.json` | Col's hooks, added next to yours; the previous file is kept as `<file>.col-backup` | Read to show which agents are connected; written when you connect one, and disconnecting removes them |
| `~/Library/Application Support/Islet/`, `~/Library/Caches/Islet/` | Where Islet kept the same files: on the first launch of Col they move to Col's folders, and nothing else is changed | Once, when you update from Islet |
| `Islet.app`, where the update installed it | Renamed Col.app, and an older Islet.app left beside it or in Applications goes to the Trash. A copy installed with Homebrew keeps its name, so `brew` can still upgrade and remove it: `brew upgrade --cask --greedy col` replaces it with Col.app | Once, when you update from Islet |

Clipboard history (except the text you pin) and the pictures you copy stay in memory and are never written to disk.
Copies that password managers mark as concealed or transient are skipped.

### Processes

- `/usr/bin/perl`, running Col's small media helper (`Contents/Frameworks/libColMediaBridge.dylib`) to read what is
  playing. Since macOS 15.4 only Apple-signed processes may read the now playing information.
- Your extensions' scripts, on the schedule each one declares, with your user's rights. macOS treats each one as a
  program of its own: it never inherits Col's Accessibility, Microphone, Camera or Calendars permissions.

### Network

- The update check: Sparkle reads `https://getcol.vercel.app/appcast.xml` once a day, and downloads new versions
  from GitHub. Updates are signed with Col's EdDSA key and verified before they are opened. Sparkle's system profile
  is off. You can turn automatic checks off in Settings, General.
- Lyrics, while they are on (Settings, Music and lyrics): the title, the artist, the album and the length of the
  song that plays are sent to [LRCLIB](https://lrclib.net), an open lyrics database, once per song. Answers are kept in
  `~/Library/Caches/Col/Lyrics/`; your own `.lrc` files in `~/Library/Application Support/Col/Lyrics/` are read
  first and never sent anywhere. Lyrics are on in a new install, where the welcome shows the choice; after an update
  from Islet they stay off until you turn them on.
- The AI servers you add in Settings, AI apps, and the Ollama or LM Studio of this Mac when they are installed:
  Col asks them every few seconds, only while their page or the settings show them, for their models
  (`/api/tags`, `/api/ps`, `/api/v0/models`, `/v1/models`, `/slots`). A token you give is kept in your Keychain and
  sent only to that server. Col reaches each server at the address you typed, over https or plain http: model servers
  on a home network often speak only http, so App Transport Security allows it. Over http, what you send, a token
  included, crosses your network unencrypted.
- A question you ask from the AI page goes to the server and model you picked, and nowhere else, with the conversation
  so far (the last twenty messages at most). The conversation stays in memory until you start a new one or quit Col;
  it is never written to disk.
- The prompter's phone remote, off until you turn it on in Settings, Prompter: a small web server on your local
  network (port 7575 to 7579) that only answers a phone carrying the pairing code of the QR code you scanned. It
  stops when you turn the remote off. Nothing goes to the internet.
- Nothing else. No account, no telemetry, no analytics, no crash reports.

### Permissions

Each one only if a module you chose needs it: Accessibility (the volume and brightness keys, and measuring the menu
bar), Calendars and Reminders (the agenda), Bluetooth (headphone battery and model), Camera (only while the mirror
is open), Microphone (the prompter's voice modes, while a take runs: the sound is analysed on your Mac and never
recorded), Speech Recognition (the prompter's Voice Follow, on your Mac only), Local Network (the prompter's phone
remote, and the AI servers you add on another machine). The colour picker uses the system's own sampler, which asks
for nothing.

### Login item

When you choose Open at Login, Col registers itself with `SMAppService`. It shows in System Settings, General,
Login Items. After an update from Islet, the login item is registered again for Col.app.

### Private macOS APIs

MediaRemote (now playing), DisplayServices (brightness), undocumented `IOBluetoothDevice` properties (headphone
battery and model), `CABackdropLayer`, `CAFilter` and the `glassBackground` filter of Liquid Glass (the Liquid and Transparent glass of the
open island) and SkyLight (the Lock
Screen, off by default). Each is looked up at run time: if a macOS update
removes one, its feature turns off and nothing crashes. The [README](README.md#private-macos-apis) says why each is
needed.
