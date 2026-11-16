# Homebrew Outdated

How many Homebrew packages have a newer version, with the first three named, as a widget. Up to date, it says so in
green.

- **Shows**: a widget in the island's Widgets place.
- **Needs**: [Homebrew](https://brew.sh).
- **Runs**: every hour. It reads what Homebrew already knows (`brew outdated`) and never updates Homebrew's index
  itself: `brew update` stays yours to run.

```sh
colctl extensions install examples/extensions/homebrew-outdated --on
```
