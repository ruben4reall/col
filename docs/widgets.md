# Widgets

A widget is a small card in the island: a figure with its unit, a bar, a few lines and up to three buttons. Your
scripts, your devices and web addresses fill it; it shows in the **Widgets** place, which you add to any page in
Settings, Pages (or in one click in Settings, Connect, Add a Widgets Page). Half a page shows one widget at a time,
a whole page two, with dots to go to the others.

One format, wherever it comes from:

| From | How |
|---|---|
| A script on this Mac | `colctl widget set <id> --json widget.json`, or the [local API](api.md): `PUT /v1/widgets/<id>` |
| Your phone, a home server, Home Assistant, a build machine | [Col Connect](connect.md): the same `PUT /v1/widgets/<id>`, over the local network |
| An extension | the script prints `{"widget": {...}}` ([extensions](extensions.md)) |
| A web address | Settings, Connect, Add a Widget from a URL: Col reads it at the interval you choose, only while the widget shows |

## The format

```json
{
  "title": "Living room",
  "value": 21.5,
  "unit": "°C",
  "progress": 0.4,
  "symbol": "thermometer.medium",
  "tint": "orange",
  "lines": ["Humidity 48%", "Window closed"],
  "buttons": [
    {"title": "Heat", "url": "http://homeassistant.local:8123/api/webhook/heat", "symbol": "flame.fill"}
  ],
  "staleAfter": 900,
  "activity": false
}
```

| Field | | |
|---|---|---|
| `id` | | Letters, digits, `.`, `-` and `_`, 64 at most. The address `/v1/widgets/<id>` gives it: in a body it is optional. Setting a widget again with the same id updates it |
| `title` | text | Beside the symbol, 60 characters at most |
| `value` | text or number | The figure, large. A number is written the way people read it: `21.5`, `3`, `1200` |
| `unit` | text | After the value, smaller: `°C`, `%`, `runs` |
| `progress` | 0 to 1 | A bar under the value |
| `symbol` | SF Symbol | Beside the title, in the tint |
| `tint` | colour | `white`, `green`, `orange`, `red`, `blue`, `purple`, `yellow`, `pink`, `teal`, `gray`, or `#RRGGBB` |
| `lines` | up to 3 texts | Under the value, 80 characters each; more lines are left out |
| `buttons` | up to 3 | Each with a `title`, a `url` (http or https only), a `method` (`POST`, the default, or `GET`) and an optional `symbol` |
| `staleAfter` | seconds | When the figures are older than this, the widget dims and says when they arrived. 10 seconds to a week |
| `activity` | true or false | Also show the widget beside the camera in the closed island: its symbol on the left, its value or progress on the right, until it goes stale |

Text too long is cut to the lengths above. A widget is refused, with a `400` saying why, when its id is not one of the
characters allowed, when it has more than three buttons, or when a button has no title or an address that is not
http or https.

## Buttons

Pressing a button calls its address from your Mac: a `POST` with the body `{"widget": "<id>", "button": "<title>"}`,
or a `GET`. The first time a button calls an address, the island shows the method and the whole address and asks
before calling it; once you say yes, that address is called at once from then on. The button shows a check mark when
the address answers 2xx, a warning otherwise. Buttons never open files, apps or other schemes.

## Pushing a widget

From a script on this Mac:

```sh
colctl widget set ci --title "CI" --value Passed --symbol checkmark.seal.fill --tint green --stale-after 3600
colctl widget set temp --json widget.json
some-command | colctl widget set temp --json -
colctl widget set build --value 12 --unit "of 40" --progress 30% --line "Compiling Parser.swift" --activity
colctl widget list
colctl widget remove temp
```

Options given after `--json` change the fields of the file. `--line` can be given up to three times.

With curl, on the local socket:

```sh
curl --unix-socket "$HOME/Library/Application Support/Col/col.sock" \
  -X PUT http://col/v1/widgets/temp \
  -d '{"title":"Living room","value":21.5,"unit":"°C","symbol":"thermometer.medium","tint":"orange"}'
```

From another device, through [Col Connect](connect.md), with its token:

```sh
curl -X PUT http://192.168.1.20:7580/v1/widgets/temp \
  -H "Authorization: Bearer $COL_TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"Living room","value":21.5,"unit":"°C","staleAfter":900}'
```

Pushed widgets are kept in `~/Library/Application Support/Col/Widgets.json` (readable by you only), so they are still
there after a restart, dimmed once stale. `DELETE /v1/widgets/<id>` or `colctl widget remove <id>` takes one away;
so does its minus button in Settings, Connect.

## A widget from a web address

Settings, Connect, **Add a Widget from a URL**:

- **Address**: any http or https address that answers JSON.
- **Read**: every 1, 5, 15, 30 or 60 minutes, and only while the widget shows in the island. Nothing is read while
  the island is closed or shows another page.
- **Headers**: a token or a key, if the address needs one (`Authorization`, `X-Api-Key`). Their values are kept in
  your Keychain, never in Col's settings.
- **What the widget shows**: each field is plain text, or a key path of the answer in braces:

  | Field | Example |
  |---|---|
  | Title | `{location.name}` or `Weather` |
  | Value | `{current.temp_c}` |
  | Unit | `°C` |
  | Progress | `{battery}`, out of `100` (without a maximum, a number above 1 counts as a percentage) |
  | Lines | `Feels like {current.feelslike_c}°`, `{forecast.days.0.summary}` |

  Key paths go through objects with dots and through arrays with numbers: `data.items.0.name` or `data.items[0].name`.
  `{{` and `}}` write a brace.

- Leave every field empty when the address answers in Col's own format, the JSON above: then the answer is the widget.

**Read Now** reads the address once and shows the answer beside the widget it gives, as you change the fields. A key
path that leads nowhere shows as `–`, and the preview names it. A widget read from an address goes stale once two reads
have been missed.

## From an extension

An extension's script prints the widget under `widget`, alone or beside an activity:

```json
{"widget": {"title": "Homebrew", "value": 3, "unit": "outdated", "symbol": "mug.fill"}}
```

The widget's id is `ext-<folder>`. A run that prints nothing takes the extension's widget away, as it does its
activity. See the [catalog of examples](extensions.md#catalog).
