# Website Status

Whether a website answers, and how fast, as a widget. When it stops answering, or answers with an error, an alert
shows in the closed island too, until it answers again.

- **Shows**: a widget in the Widgets place, and an alert beside the camera while the site is down.
- **Needs**: nothing but macOS (`curl`).
- **Runs**: every minute, one request to the address, eight seconds at most.

Set the address at the top of `check.sh`, then:

```sh
colctl extensions install examples/extensions/website-status --on
```

Install it again under another name for each site: `--name status-blog`.
