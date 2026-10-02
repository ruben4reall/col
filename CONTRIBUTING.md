# Contributing to Col

Thank you for helping. A few principles keep Col what it is.

## Principles

- **Light.** Nothing polls when nothing changes. Prefer notifications (Core Audio, IOKit, EventKit) over timers, and
  animations that run in the render server over per-frame work in the app. Measure with `scripts/bench.sh <pid>`
  before and after a change that could cost memory or processor time.
- **Native.** AppKit and Core Animation for the island, SwiftUI for its content. No web views.
- **Private.** No network calls beyond the update check, the lyrics lookups (which can be turned off) and what the user
  adds and turns on, no analytics. Anything sensitive stays in memory.
  [SECURITY.md](SECURITY.md) lists everything Col touches: keep it true.
- **Tested rules.** Behaviour that can be expressed without AppKit belongs in `ColCore`, with tests.
- **Clean-room.** Col is MIT licensed. Do not copy code from projects under other licences, including GPL notch apps.

## Workflow

1. `scripts/build.sh` and `swift test --package-path Packages/ColKit` must pass without warnings. To run a build next
   to the Col you use, give it a socket of its own: `COL_SOCKET=/tmp/col-dev.sock`, so your agents keep
   talking to yours. Without it, a build with the same identifier as the running Col hands over to it and quits.
2. User-facing strings go through the string catalogs (`Localizable.xcstrings`), in English. Add the other languages
   when you can; see [Translations](#translations).
3. One change per pull request, with a screenshot or a short video for anything visible.
4. For the website: `node site/tools/audit.mjs` must be clean (errors, broken images, overflow, contrast), and every
   picture of the app comes from the app itself, through `scripts/capture-site.sh`.

## Translations

Col follows the language of the Mac, and Settings > General > Language picks another one. Every translation was
made by AI, not by native speakers: some words will sound wrong, and fixing them is one of the most useful
contributions there is.

- The strings live in five catalogs (open them in Xcode, or edit the JSON):
  - `Packages/ColKit/Sources/ColShell/Resources/Localizable.xcstrings`: the island, its pages, the settings and the
    welcome.
  - `Packages/ColKit/Sources/ColPrompter/Resources/Localizable.xcstrings`: the prompter, its Scripts window and the
    phone remote's page.
  - `App/Localizable.xcstrings`: the Shortcuts actions and the app's own alerts.
  - `App/AppShortcuts.xcstrings`: the phrases that start Col's App Shortcuts; keep `${applicationName}` as it is.
  - `App/InfoPlist.xcstrings`: what macOS says when it asks for a permission.

  Change the wording of your language, keep the placeholders (`%@`, `%lld`) and the tone: short, plain, friendly, no
  jargon.
- One pull request per language is easiest to review. Say in it that you speak the language natively.
- A new language is welcome too: add it to `CFBundleLocalizations` in `project.yml` and fill every catalog.

## Where things live

See the table in the [README](README.md#build-from-source).
