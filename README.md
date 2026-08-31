# DoseKeeper — one medication truth across five care perspectives

[![Flutter CI](https://github.com/Xyloth/dosekeeper/actions/workflows/ci.yml/badge.svg)](https://github.com/Xyloth/dosekeeper/actions/workflows/ci.yml)
[![Deploy to GitHub Pages](https://github.com/Xyloth/dosekeeper/actions/workflows/pages.yml/badge.svg)](https://github.com/Xyloth/dosekeeper/actions/workflows/pages.yml)
[![Windows build](https://github.com/Xyloth/dosekeeper/actions/workflows/windows.yml/badge.svg)](https://github.com/Xyloth/dosekeeper/actions/workflows/windows.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-0E7C7B.svg)](LICENSE)

DoseKeeper is a deployed Flutter/Riverpod care-coordination demo built around one deliberately strict idea: **taken, missed, and not marked are three different states**. A person marks a dose in the Patient view, and the Caregiver and Provider views react to the same persisted state graph without screens passing data to one another.

> The care circle and medication names are fictional. DoseKeeper is a personal/family coordination demo, not a medical device. It does not provide dosage guidance, interaction checking, reminders guaranteed to fire, or medical advice.

**[Open the live demo](https://xyloth.github.io/dosekeeper/)** · **[Read the design contract](DESIGN.md)** · **[Inspect the CI](https://github.com/Xyloth/dosekeeper/actions/workflows/ci.yml)**

## Prove it in 60 seconds

No account or setup is required. The banner identifies the bundled family as fictional.

1. In **Grandma Rose**, mark an amber dose as taken.
2. Open **Caregiver**. The attention count and Rose's status update from the same state mutation—no refresh.
3. Open **Provider**. The identical event appears in the live Today panel and the three-state history.
4. Move the labeled **Demo clock** beyond a dose window. The app asks a human to distinguish “missed” from “taken, forgot to mark”; it never guesses.
5. Correct or undo the answer and watch every perspective reconcile again.

| Patient mutation | Caregiver consequence | Provider consequence |
| --- | --- | --- |
| ![Patient view with one taken dose and unresolved amber doses](docs/screenshots/patient.png) | ![Caregiver dashboard separating a confirmed miss from unresolved doses](docs/screenshots/caregiver.png) | ![Provider live Today panel and adherence history](docs/screenshots/provider.png) |

### Engineering evidence behind the interaction

| Claim | Verifiable evidence |
| --- | --- |
| One state graph feeds five role views | Riverpod derived providers over `careCircleProvider`; widget tests perform a Patient tap and assert Caregiver and Provider output. |
| The three-state invariant survives time and reloads | Domain, persistence, injected-clock, threshold, rollover, and correction tests run in CI. |
| It ships, rather than stopping at screenshots | GitHub Pages builds and deploys the web release; a separate Windows runner compiles the x64 bundle. |
| The architecture has a defined boundary | `LocalRepo` implements the repository contract today; cloud sync is explicitly a future implementation, not a current claim. |

## What the demo proves

- **Five perspectives, one state graph:** Patient, Caregiver, Provider, Circle, and Settings all watch Riverpod providers derived from one persisted care-circle snapshot.
- **A visible cross-role invariant:** tapping the amber “Taken?” action changes the Patient dose, Caregiver attention count, Provider Today panel, and relevant badges immediately.
- **Three-state integrity:** an unresolved dose stays amber and remains `notMarked`; only a human can resolve it as green `taken` or red `missed`.
- **Human escalation:** a labeled demo clock moves a dose from heads-up to window-closing to “Did you take it and forget to mark it, or did you miss it?”
- **Correctable history:** a mistaken answer can be corrected or undone, with the same update propagating everywhere.
- **Deterministic time behavior:** injected date/time providers make threshold and midnight-rollover behavior testable instead of depending on the wall clock.
- **Offline persistence behind a boundary:** `LocalRepo` stores JSON with `shared_preferences` and exposes a watch contract. A future synchronized repository can feed the same state layer; Firestore is not implemented in v0.1.

## Screens

| View | Purpose |
| --- | --- |
| Patient | Large, simple dose cards; mark taken; answer unresolved-dose questions; correct an entry. |
| Caregiver | Prioritized attention list and per-person today/week status, including confirmed misses. |
| Provider | A live Today panel plus date-range history that preserves taken/missed/not-marked distinctions. |
| Circle | Read-only fictional people, medications, and human-readable schedules. |
| Settings | Demo-clock explanation, example-data reset, persistence state, and safety/disclaimer information. |

## Remaining verified release views

These are deterministic 1440×1000 captures of the full Flutter widget tree with the bundled fictional family—not mockups.

| Circle | Settings |
| --- | --- |
| ![Fictional care circle and schedules](docs/screenshots/circle.png) | ![Settings, persistence state, demo clock explanation, and disclaimer](docs/screenshots/settings.png) |

[`docs/screenshots/`](docs/screenshots/) contains the reproducible capture command and state contract.

## Architecture

```mermaid
flowchart LR
    UI["Patient · Caregiver · Provider · Circle · Settings"]
    DERIVED["Riverpod derived providers<br/>today · attention · adherence · settings"]
    STORE["careCircleProvider<br/>single in-memory source of truth"]
    REPO["Repository watch/save contract"]
    LOCAL["LocalRepo<br/>shared_preferences JSON"]
    FUTURE["Future sync repository<br/>not included in v0.1"]

    UI -->|watch| DERIVED
    UI -->|mutate| STORE
    STORE --> DERIVED
    STORE <--> REPO
    REPO <--> LOCAL
    FUTURE -. same contract .-> REPO
```

The UI never passes a mutated model from one role screen to another. It sends an intent to the notifier; derived providers recompute, and every interested view rebuilds from the new snapshot. Persistence writes are kept behind the repository rather than embedded in widgets.

The event key is a schedule slot plus local calendar date. An event records `taken` (including when it was recorded), `missed` (explicitly confirmed), or no event, which derives to `notMarked`. Known-history boundaries keep dates outside the seeded data from being reported as non-adherence.

## Run locally

Prerequisites: [Flutter 3.44.6 stable](https://docs.flutter.dev/get-started/install) (Dart 3.12.2) and a web-capable device.

```powershell
git clone https://github.com/Xyloth/dosekeeper.git
cd dosekeeper/app
flutter pub get
flutter run -d chrome
```

The app opens with a clearly labeled fictional family. Use **Demo clock** to cross a dose-window boundary without changing the computer clock. Use **Settings → Reset fictional example family** to restore the known starting state.

For Windows desktop:

```powershell
flutter config --enable-windows-desktop
flutter run -d windows
```

Windows plugin builds require symlink support. Enable Windows Developer Mode if Flutter reports that plugins cannot create symlinks.

## Verify

Run the same gates used in CI:

```powershell
cd app
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release
```

The tests cover domain-state integrity, persistence/reload behavior, time boundaries, selection stability, and the headline widget flow: a Patient interaction updates Caregiver and Provider UI from shared state.

## Deployment

[`pages.yml`](.github/workflows/pages.yml) builds with the repository base path and deploys the release artifact to GitHub Pages on pushes to `main`. In repository settings, choose **GitHub Actions** as the Pages source. The workflow requests only `contents: read`, `pages: write`, and the OIDC permission required by Pages.

[`windows.yml`](.github/workflows/windows.yml) is a manual bonus-platform build so normal pull requests do not spend Windows runner minutes. [`ci.yml`](.github/workflows/ci.yml) enforces formatting, analysis, tests, and the web release build.

## Scope and privacy

v0.1 has no accounts, server, analytics, PHI workflow, OS notifications, drug database, or cloud synchronization. Data remains in the browser/app’s local preferences. Clearing site/app storage removes it. Do not enter real health information into this portfolio demo.

See [`DESIGN.md`](DESIGN.md) for the product decisions and [`CHANGELOG.md`](CHANGELOG.md) for the current verification state.

## License

MIT © 2026 James Dye. See [`LICENSE`](LICENSE).
