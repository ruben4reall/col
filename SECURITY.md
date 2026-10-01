# Security

## Reporting a vulnerability

Please open a [private security advisory](https://github.com/ruben4reall/islet/security/advisories/new) rather than a
public issue. You will get an answer within a few days.

## What Islet touches on your Mac

Everything Islet reads, writes or runs, and why.

### Files

| Path | What | When |
|---|---|---|
| `~/Library/Preferences/ch.rubencatalao.islet.plist` | Settings, the shelf's file bookmarks, pinned clipboard text | Always |
| `~/Library/Application Support/Islet/islet.sock` | The local socket scripts and agents talk to: mode 0600 in a 0700 folder, so only your user can connect. It never listens on the network | While Islet runs |
| `~/Library/Application Support/Islet/Extensions/` | Your extensions, one folder each | When you add one |
| `~/Library/Application Support/Islet/Scripts/` | The prompter's scripts, one Markdown file each, saved as you type. The first time, the scripts of Souffleur (the prompter's former app) are copied in from `~/Library/Application Support/Souffleur/Scripts/`, which is left as it was | When you use the prompter |
| `~/.local/bin/islet` | A link to the `islet` command inside the app | When you install the command |
| `~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.gemini/settings.json`, `~/.cursor/hooks.json`, `~/.copilot/hooks/islet.json` | Islet's hooks, added next to yours; the previous file is kept as `<file>.islet-backup` | When you connect that agent; disconnecting removes them |

Clipboard history (except the text you pin) and the pictures you copy stay in memory and are never written to disk.
Copies that password managers mark as concealed or transient are skipped.

### Processes

- `/usr/bin/perl`, running Islet's small media helper (`Contents/Frameworks/libIsletMediaBridge.dylib`) to read what is
  playing. Since macOS 15.4 only Apple-signed processes may read the now playing information.
- Your extensions' scripts, on the schedule each one declares, with your user's rights.

### Network

- The update check: Sparkle reads `https://getislet.vercel.app/appcast.xml` once a day, and downloads new versions
  from GitHub. Updates are signed with Islet's EdDSA key and verified before they are opened. Sparkle's system profile
  is off. You can turn automatic checks off in Settings, About.
- Lyrics, while they are on (Settings, Music and lyrics): the title, the artist, the album and the length of the
  song that plays are sent to [LRCLIB](https://lrclib.net), an open lyrics database, once per song. Answers are kept in
  `~/Library/Caches/Islet/Lyrics/`; your own `.lrc` files in `~/Library/Application Support/Islet/Lyrics/` are read
  first and never sent anywhere.
- The AI servers you add in Settings, AI apps, and the Ollama or LM Studio of this Mac when they are installed:
  Islet asks them every few seconds, only while their page or the settings show them, for their models
  (`/api/tags`, `/api/ps`, `/api/v0/models`, `/v1/models`, `/slots`). A token you give is kept in your Keychain and
  sent only to that server.
- A question you ask from the AI page goes to the server and model you picked, and nowhere else, with the conversation
  so far (the last twenty messages at most). The conversation stays in memory until you start a new one or quit Islet;
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
remote). The colour picker uses the system's own sampler, which asks for nothing.

### Login item

When you choose Open at Login, Islet registers itself with `SMAppService`. It shows in System Settings, General,
Login Items.

### Private macOS APIs

MediaRemote (now playing), DisplayServices (brightness), undocumented `IOBluetoothDevice` properties (headphone
battery and model), `CABackdropLayer`, `CAFilter` and the `glassBackground` filter of Liquid Glass (the Liquid and Transparent glass of the
open island) and SkyLight (the Lock
Screen, off by default). Each is looked up at run time: if a macOS update
removes one, its feature turns off and nothing crashes. The [README](README.md#private-macos-apis) says why each is
needed.
