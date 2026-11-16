# Col Connect

Col Connect lets the devices of your local network push into the island: your iPhone through a Shortcut, Home
Assistant when the washing machine is done, a Raspberry Pi with the temperature of the living room, a build machine
with its progress. They reach the same routes as the [local API](api.md), over HTTP on your network, each with a token
of its own.

Connect is **off** until you turn it on in Settings, Connect. Turned on, it listens on port 7580 (or the next one
free up to 7584), and macOS asks once for the Local Network permission. Turned off, it stops listening.

## Pair a device

1. Settings, Connect: turn on **Col Connect**.
2. **Pair a Device…**, give it a name (iPhone, Home Assistant, build server), then **Pair**.
3. A QR code, the address and the token appear:
   - On a phone, scan the code with the camera. A page of your Mac's opens with the address and the token, each with
     a Copy button, and **Send a Test to the Island**.
   - Elsewhere, copy the token with **Copy Token**, and type the address.

Each device has its own token. **Show Code** shows it again; **New Token** replaces it (the old one stops working at
once); the minus button forgets the device and its token. The list shows when each device was last seen, and from
which address.

The address is your Mac's on this network, `http://192.168.1.20:7580`, and also its Bonjour name,
`http://Your-Mac.local:7580`, which keeps working when the Mac's address changes. Col advertises itself as
`_col._tcp`: `dns-sd -B _col._tcp` lists the Macs running Connect.

## Requests

Every request carries the device's token in a header:

```
Authorization: Bearer <token>
```

| Method and path | Body | Answer |
|---|---|---|
| `GET /v1/status` | | `{"app": "Col", "version": "2.4.0", "activities": 1, "widgets": 2}` |
| `POST /v1/activities` | an [activity](api.md#what-an-activity-shows) | `{"id": "build"}` |
| `POST /v1/activities/<id>/done?text=Done` | | `{"id": "build"}` |
| `DELETE /v1/activities/<id>` | | `{"id": "build"}` |
| `PUT /v1/widgets/<id>` | a [widget](widgets.md) | `{"id": "temp"}` |
| `DELETE /v1/widgets/<id>` | | `{"id": "temp"}` |

Activities and widgets pushed through Connect are the same as those pushed on the Mac: `colctl done build` finishes
an activity a build machine started.

Nothing else is reachable from the network. In particular, **agents' permission requests never are**: Allow and Deny
stay on the Mac, in the island and in the terminal. A device cannot list what runs on the Mac either.

| Status | Means |
|---|---|
| `400` | The body is not an activity or a widget; the answer says what to fix |
| `401` | No token, or not a paired device's |
| `404`, `405` | A route Connect does not have, or a method it does not take there |
| `411` | A chunked body: send a `Content-Length` |
| `409` | Col already holds 32 activities, or 32 widgets, pushed by programs: remove one, or let one end. Updating one already there always works |
| `413`, `431` | A body over 64 KB, or headers over 8 KB |
| `429` | Too many requests from this address: 60 at once, then 20 a second. After ten wrong tokens, an address waits thirty seconds for each new try |

## iPhone: a Shortcut

A Shortcut that puts "Leaving work" in the island, for a minute:

1. Open **Shortcuts** and tap **+**.
2. Search for **Get Contents of URL** and add it.
3. Tap **URL** and type the address of Settings, Connect, followed by `/v1/activities`:
   `http://192.168.1.20:7580/v1/activities`.
4. Tap the arrow beside the action to show more:
   - **Method**: POST.
   - **Headers**: **Add new header**. Key `Authorization`, value `Bearer ` followed by the token (one space between).
   - **Request Body**: JSON. Add these fields:
     | Key | Type | Value |
     |---|---|---|
     | `id` | Text | `phone` |
     | `title` | Text | `Leaving work` |
     | `symbol` | Text | `car.fill` |
     | `tint` | Text | `blue` |
     | `ttl` | Number | `60` |
5. Name the Shortcut and run it: the island shows it beside the camera.

Run it from an automation (when you leave a place, when a focus starts), from Back Tap, or from the Action button.

A widget with the phone's battery, updated by an automation:

1. Add **Get Battery Level**.
2. Add **Get Contents of URL** with `http://192.168.1.20:7580/v1/widgets/iphone`, **Method** PUT, the same
   `Authorization` header, and a JSON body: `title` (Text) `iPhone`, `value` (Number) the **Battery Level** variable,
   `unit` (Text) `%`, `symbol` (Text) `iphone`, `staleAfter` (Number) `3600`.

## curl

```sh
COL=http://192.168.1.20:7580
TOKEN=…   # Settings, Connect, Copy Token

curl -s $COL/v1/status -H "Authorization: Bearer $TOKEN"

# A build that reports its progress, then is done.
curl -s -X POST $COL/v1/activities -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"id":"build","title":"Release build","symbol":"hammer.fill","tint":"orange","progress":0.4}'
curl -s -X POST "$COL/v1/activities/build/done?text=Shipped" -H "Authorization: Bearer $TOKEN"

# A widget.
curl -s -X PUT $COL/v1/widgets/server -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"NAS","value":71,"unit":"%","progress":0.71,"symbol":"externaldrive.fill","lines":["2.1 TB free"],"staleAfter":900}'
curl -s -X DELETE $COL/v1/widgets/server -H "Authorization: Bearer $TOKEN"
```

## Home Assistant

In `secrets.yaml`, the token with its `Bearer` (a device paired as "Home Assistant"):

```yaml
col_authorization: "Bearer YOUR_TOKEN"
```

In `configuration.yaml`, two commands:

```yaml
rest_command:
  col_activity:
    url: "http://192.168.1.20:7580/v1/activities"
    method: POST
    headers:
      Authorization: !secret col_authorization
    content_type: "application/json"
    payload: >
      {"id": "{{ id }}", "title": "{{ title }}", "symbol": "{{ symbol | default('house.fill') }}",
       "tint": "{{ tint | default('blue') }}", "ttl": {{ ttl | default(300) }}}
  col_widget:
    url: "http://192.168.1.20:7580/v1/widgets/{{ id }}"
    method: PUT
    headers:
      Authorization: !secret col_authorization
    content_type: "application/json"
    payload: "{{ widget | to_json }}"
```

Then, in automations:

```yaml
- alias: "Washing machine done, in Col"
  triggers:
    - trigger: state
      entity_id: sensor.washing_machine_status
      to: "idle"
  actions:
    - action: rest_command.col_activity
      data:
        id: washer
        title: "Washing done"
        symbol: washer.fill
        tint: teal
        ttl: 900

- alias: "Living room in Col"
  triggers:
    - trigger: state
      entity_id: sensor.living_room_temperature
  actions:
    - action: rest_command.col_widget
      data:
        id: living-room
        widget:
          title: "Living room"
          value: "{{ states('sensor.living_room_temperature') }}"
          unit: "°C"
          symbol: thermometer.medium
          tint: orange
          staleAfter: 3600
          buttons:
            - title: "Heat"
              url: "http://homeassistant.local:8123/api/webhook/col-heat"
```

The **Heat** button calls a Home Assistant webhook (a trigger of type Webhook with the id `col-heat`) from your Mac.
The first time, the island shows the address and asks before calling it.

## Security

- Off by default. On, it answers only devices of your local network (private, link-local and loopback addresses, and
  the global IPv6 addresses of the Mac's own Wi-Fi or Ethernet network, which a phone often uses to reach a `.local`
  name), unless you turn on **Accept connections from outside this network** for a VPN or a forwarded port.
- Every request needs a paired device's token, compared in constant time. Tokens are 32 random bytes, kept in your
  Keychain, never in Col's settings, and each one can be replaced or taken back on its own.
- Requests are plain HTTP: on a network you do not trust, someone listening could read a token. Pair devices on your
  own network, and take back a token you think was seen.
- The page the QR code opens holds no secret: the token stays in the address's fragment (after `#`), which the phone
  never sends.
- Bodies over 64 KB, headers over 8 KB and chunked bodies are refused before they are read; each address has a rate,
  and wrong tokens slow the guesser down.
- No route reaches an agent: Allow and Deny stay on the Mac.

More in [SECURITY.md](../SECURITY.md#col-connect).
