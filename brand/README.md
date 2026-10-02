# Col brand

**Name**: Col, Islet until 2.0. A col is the pass between two peaks, and the collar of a shirt: the notch, cut into
the top of the screen between its two halves. Three letters, said the same in English and French.
**Tagline**: The notch, made useful. (FR: L'encoche, enfin utile.)

## Icon

A slab of polished black glass with a notch-shaped window at its top edge, lit in Apple blue from within: the light rises
from the bottom of the window and spills onto the glass below it. Drawn by `scripts/glow-icon.swift` at every size of
the asset catalog (`App/Assets.xcassets/AppIcon.appiconset`), and at 1024 px in `icon-1024.png`.

```sh
swiftc -O -o /tmp/glow brand/scripts/glow-icon.swift && /tmp/glow notch brand/icon-1024.png 1024
```

## Colour

| Token | Hex | Use |
|---|---|---|
| Night | `#05080A` | The island, dark surfaces |
| Blue | `#0A84FF` | macOS's own blue: the icon's light, the website and anything printed |
| Deep blue | `#0060DF` | Gradients and pressed states |
| Sky | `#B8DAFF` | The brightest light in the icon and gradients |
| Ink | `#0F1B1F` | Text on light surfaces |

Inside the app, the accent is the one you chose for your Mac (System Settings, Appearance): Col has no colour of its
own there, as Apple's apps do not.

Semantic colours inside the island follow macOS: green `#33D666` for done and charging, orange `#FF9F0A` for waiting
and timers, red `#FF453A` for denied and low battery.

## Type

- Inside the app: the system font (SF Pro, SF Pro Rounded for the clock).
- Website: see `site/`.

## Voice

Short, concrete, calm. Say what happens. No exclamation marks, no em dashes.
