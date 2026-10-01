# Changelog

Each release's section is what Islet's update window and the GitHub release show. Dates are in ISO format.

## 2.0.0 (unreleased)

- **New settings**: a bigger window that opens below the island instead of under it, grouped panes with a search
  field, and headers that stay put while the settings scroll beneath them. Appearance and Pages show your own island,
  drawn by Islet itself on your wallpaper with what it shows right now, and every change of size or glass also plays
  on the notch. While the settings are open, Islet has a Dock icon and menus, so ⌘Tab, copy and paste work as anywhere.
- **Synced lyrics**: the words of the song beside the player, line by line, the way Apple Music shows them, whatever
  plays (Spotify, Apple Music, Deezer, your browser). Tap a line to jump there; long instrumental passages breathe
  three dots. Optionally, the line being sung in the closed island. Lyrics come from LRCLIB, an open database: only
  the title, the artist, the album and the length of the track are sent, and the answer is kept on your Mac. Your own
  `.lrc` files take precedence. Settings, Music and lyrics.
- **The prompter, in the notch**: Souffleur joins Islet. Your script comes out of the notch right under the camera
  and rolls at the pace of your voice: it waits when you stop talking (Voice Pace), follows your words one by one
  (Voice Follow), rolls at a steady pace, or moves only when you move it. It lives on a page of the island with its
  play button, has its own Scripts window and its own pane in Settings, and stays out of screenshots, recordings and
  calls. While it is out, the island steps aside and comes back after the take. Drive it with ⌃⌥⌘P and its other
  shortcuts, a presentation clicker, your phone, Shortcuts actions or `islet://prompter/…` links. If you used
  Souffleur, your scripts and settings carry over, and its `souffleur://` links keep working.
- **Pages you compose**: each page of the open island holds one widget across it or two side by side, and each place
  can stack several widgets: the island shows the first one that has something to show. Home now puts the player
  beside the agenda (the clock while nothing plays). Add, rename, reorder and remove pages in Settings, Pages, where
  the island shows the page as you edit it. Your pages from Islet 1 carry over.
- **What the closed island shows first**: when several things run at once, the order is yours (Settings, Live
  activities). Volume, brightness, alerts and requests still come first.
- **AI apps, all of them**: Islet recognizes the AI apps on your Mac (Claude, ChatGPT, Gemini, Perplexity, Grok Bot,
  Cursor, VS Code, Zed, Ollama, LM Studio and more) with their own icons, and shows the open ones on an AI page of the
  island, a tap away. Add your own AI: an Ollama, LM Studio, llama.cpp or OpenAI-compatible server on this Mac or on
  another machine of your network; the island shows whether it answers, the model it holds and, when the server can
  tell, whether it is generating. Tokens stay in your Keychain. Settings, AI apps.
- **Agents show their logo**: Claude Code shows Claude's logo, and Codex, Gemini CLI, Cursor and GitHub Copilot theirs,
  in the closed island, on the Live page, on the AI page and in the settings. The icon of the app installed when there
  is one, else the brand's own logo, which Islet carries. The logo bounces, as in the Dock, while the agent needs you
  (not with Reduce Motion). Each icon is kept only at the size it shows.
- **More pages fit**: six tabs fit beside the camera; with more pages, the tabs become dots, as on the iPhone.
- **Permissions**: one pane says what each permission is for and which feature needs it.
- **Shortcuts and gestures**: every way to open and drive the island, in one place.
- **Language**: Islet follows the language of your Mac, or the one you pick in Settings, General.

## 1.2.0 (2026-09-28)

- **GitHub Copilot in VS Code**, contributed by [@BonnetAdam](https://github.com/BonnetAdam): Copilot's agent sessions
  show in the notch like the other agents, with the project, the tool it runs, and Done when an answer is complete,
  through VS Code's own hooks. Connect it in Settings, Developers, or with `islet hooks install --agent copilot`. Islet
  only watches: VS Code keeps each session's own permission mode.
- **Agents**: each has its own symbol in the notch (Claude Code keeps the sparkle), and two permission requests from
  one session no longer cancel each other (also by @BonnetAdam). A request answered in the terminal leaves the island
  once its tool has run.

## 1.1.0 (2026-09-27)

- **Liquid Glass**: on macOS 26, the open island stays black where it meets the notch and melts into glass toward its
  lower edge, so it sits on your desktop instead of covering it. Choose it in Settings, Island, Liquid Glass, as macOS
  lets you choose for its own glass: Liquid (the default: clear glass that magnifies and bends what lies behind it
  along its edges, like a thick pane), Transparent (the desktop seen through, lightly blurred and dimmed), Tinted
  (Apple's frosted Liquid Glass) or Black. It stays black when Reduce transparency is on.
- **Fixed**: the battery percentage no longer breaks over two lines when the Live tab shares the top bar.

## 1.0.0 (2026-09-27)

The first release of Islet: a Dynamic Island for the MacBook notch, free and open source under the MIT License.

- **Now playing**: artwork, scrubber, controls and output picker in the island; the track peeks in the wings when it
  changes, and a swipe on the closed island skips it.
- **AI agents**: Claude Code, Codex, Gemini CLI and Cursor sessions show in the notch while they work; Claude Code's
  and Codex's permission requests get Allow and Deny buttons. No account, no login: connect each agent in one click
  from Settings. Any other agent or script reports with `islet agent`.
- **Programmable**: an `islet` command, a local API, an `islet://` URL scheme and Shortcuts actions push your own live
  activities; extensions add more.
- **Privacy**: a green or orange light when the camera or the microphone is in use, and which app is using it.
- **Every Mac**: on displays without a notch, Islet floats under the menu bar. It never covers a menu or a menu bar
  icon: when an app's menus reach the notch, the activity keeps a single wing on the free side.
- **AirPods, by model**: AirPods, AirPods Pro, AirPods Max and Beats recognised from the model they report, each
  with its own card and battery.
- **The rest of the island**: headphone battery, volume and brightness, charging, a shelf for files,
  clipboard history with pins, agenda and reminders, timers, a mirror, a color picker, system stats, keep awake,
  downloads.
- **Settings and onboarding**: turn each module on or off, reorder the pages, choose the size and the motion, and meet
  Islet in a short guided tour that asks only for the permissions your modules need.
- **Updates**: Islet checks for updates with Sparkle; every update is EdDSA-signed and notarized by Apple.
