# Third-party notices

The app contains no third-party code apart from [Sparkle](https://sparkle-project.org) (MIT), which installs updates.
Two techniques it uses were learned from open source projects, credited here:

- **Now playing on macOS 15.4 and later**: running a helper library inside `/usr/bin/perl`, which macOS entitles to
  read MediaRemote. Approach from [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) by Jonas van
  den Berg (BSD 3-Clause). Col's helper (`MediaBridge/`) is its own implementation.
- **Windows above the Lock Screen**: a SkyLight space at the notification-centre-at-lock level. Approach from
  [SkyLightWindow](https://github.com/Lakr233/SkyLightWindow) by Lakr233 (MIT). Col's `LockScreenSpace` is its own
  implementation.

## The menu bar's drawers

The drawers (`Packages/TiroirKit`) come from [Tiroir](https://github.com/ruben4reall/tiroir), by Col's author, under
the same MIT License. They include no code from the projects below: they are credited for the techniques the drawers
rewrote, and their licenses are reproduced as a courtesy.

### MenuBarHider (MIT)

How to hide menu bar icons on macOS 27 through MenuBarAgent's assessment mode restriction
(`MBAssessmentModeConfiguration`, `MBAssessmentModeAssertion` in the private `MenuBarClientCore` framework), and how
to keep Notification Center working by lifting the restriction while the pointer rests on the clock. Rewritten in
`Packages/TiroirKit/Sources/TiroirSystem/PrivateAPI.swift` and the macOS 27 engine.
<https://github.com/happy666End/MenuBarHider>

```text
MIT License

Copyright (c) 2026 Saveliy Yudin

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Ellipsis (Apache License 2.0)

How to read the macOS 27 menu bar from MenuBarAgent's Accessibility tree (one window per display, one slot per icon,
the owner from the slot's process, the `«` overflow button), how to wait until its layout settles, and how to open a
hidden app's icon by letting it through the restriction and pressing it. Rewritten.
<https://github.com/ronny/ellipsis>, Copyright 2026 Ronny Haryanto, licensed under the Apache License, Version 2.0
(<https://www.apache.org/licenses/LICENSE-2.0>).

### Hidden Bar (MIT)

The divider: a status item that grows wide enough to push the icons on its left off the screen, the technique the
drawers use on macOS 26. <https://github.com/dwarvesf/hidden>, Copyright (c) 2019 Dwarves Foundation, MIT License.

## The logos of AI apps and agents

When an AI app is installed, Col shows the app's own icon, read from the app. For an agent or a model server whose
app is not installed (Gemini CLI, GitHub Copilot, Ollama on another machine), it shows that brand's logo on a tile in
the brand's colours: the pictures in `Packages/ColKit/Sources/ColShell/Resources/Marks/`. They are drawn from the
marks and colours of [LobeHub Icons](https://github.com/lobehub/lobe-icons), under the MIT License below. The logos are
trademarks of their owners, shown only to say which app or agent is at work.

```
MIT License

Copyright (c) 2023 LobeHub

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Col for Windows and Linux

- **Col for Windows** (`windows/`) ships with the .NET 8 runtime and WPF, by Microsoft, under the MIT License, in its
  self-contained builds. Its tests use xUnit (Apache 2.0) and Microsoft's test packages (MIT), which are not shipped.
- **Col for Linux** (`linux/`) links GTK 4 and libadwaita (LGPL 2.1 or later), json-glib and libsoup (LGPL), from the
  system, and builds in [gtk4-layer-shell](https://github.com/wmww/gtk4-layer-shell) (MIT) when the system has none.
  Its own list: [linux/THIRD-PARTY-NOTICES.md](linux/THIRD-PARTY-NOTICES.md).

## The website

`site/` ships one third-party work, unchanged: the [Inter](https://rsms.me/inter/) typeface
(`site/assets/fonts/`), by Rasmus Andersson, SIL Open Font License 1.1 (`site/assets/fonts/LICENSE-Inter.txt`),
used where SF Pro is not available. The page's stylesheet is adapted from the Pli website, by the same author.

The website's pictures of macOS (the desktop and its wallpaper, the Dock's icons, the menu bar, the arrow cursor, a
TextEdit window) are screenshots of Apple's software, shown to illustrate Col running on it. They belong to Apple.
