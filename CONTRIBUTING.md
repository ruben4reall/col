# Contributing to Islet

Thank you for helping. A few principles keep Islet what it is.

## Principles

- **Light.** Nothing polls when nothing changes. Prefer notifications (Core Audio, IOKit, EventKit) over timers, and
  animations that run in the render server over per-frame work in the app. Measure with `scripts/bench.sh <pid>`
  before and after a change that could cost memory or processor time.
- **Native.** AppKit and Core Animation for the island, SwiftUI for its content. No web views.
- **Private.** No network calls beyond the update check, no analytics. Anything sensitive stays in memory.
  [SECURITY.md](SECURITY.md) lists everything Islet touches: keep it true.
- **Tested rules.** Behaviour that can be expressed without AppKit belongs in `IsletCore`, with tests.
- **Clean-room.** Islet is MIT licensed. Do not copy code from projects under other licences, including GPL notch apps.

## Workflow

1. `scripts/build.sh` and `swift test --package-path Packages/IsletKit` must pass without warnings.
2. User-facing strings go through the string catalogs (`Localizable.xcstrings`), in English. Add the other languages
   when you can; see [Translations](#translations).
3. One change per pull request, with a screenshot or a short video for anything visible.
4. For the website: `node site/tools/audit.mjs` must be clean (errors, broken images, overflow, contrast), and every
   picture of the app comes from the app itself, through `scripts/capture-site.sh`.

## Translations

Islet follows the language of the Mac, and Settings > General > Language picks another one. Every translation was
made by AI, not by native speakers: some words will sound wrong, and fixing them is one of the most useful
contributions there is.

- The strings live in `Packages/IsletKit/Sources/IsletShell/Resources/Localizable.xcstrings` (open it in Xcode, or edit
  the JSON). Change the wording of your language, keep the placeholders (`%@`, `%lld`) and the tone: short, plain,
  friendly, no jargon.
- One pull request per language is easiest to review. Say in it that you speak the language natively.
- A new language is welcome too: add it to `CFBundleLocalizations` in `project.yml` and fill the catalog.

## Where things live

See the table in the [README](README.md#build-from-source).
