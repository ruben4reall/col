# Changelog

Each release's section is what Islet's update window and the GitHub release show. Dates are in ISO format.

## 2.0.0 (unreleased)

- **New settings**: a bigger window that opens below the island instead of under it, grouped panes with a search
  field, and headers that stay put while the settings scroll beneath them. Appearance and Pages show your own island,
  drawn by Islet itself on your wallpaper with what it shows right now, and every change of size or glass also plays
  on the notch. While the settings are open, Islet has a Dock icon and menus, so ⌘Tab, copy and paste work as anywhere.
- **AI apps**: the AI tools Islet works with get a pane of their own, with each app's own icon.
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
