# Changelog

## 2026-07-11 — Phase 2 hardening

**Status:** implementation and local verification complete.

### Added

- A fifth Settings view with the safety disclaimer, demo-clock explanation, example-data reset, and persistence information.
- A live Today section in Provider so a Patient mutation is immediately visible in the appointment perspective.
- Correction/undo for human-entered dose answers.
- Injectable date/time state for deterministic threshold and midnight tests.
- Public-project documentation, MIT license, web/PWA metadata, screenshot capture contract, CI, GitHub Pages deployment, and an optional Windows build.

### Changed

- The repository boundary now includes a watch contract suitable for local reactive persistence and a future synchronized implementation.
- Caregiver attention distinguishes unresolved doses from confirmed missed doses; confirmed misses remain visible.
- The unresolved-dose prompt handles every outstanding item instead of dismissing the queue after one answer.
- Provider history respects known-data coverage and no longer treats absent pre-seed dates as non-adherence.
- Time, selected-person state, persistence writes, status semantics, and accessibility labels were hardened for long-running and narrow-screen use.

### Fixed

- Patient changes now feed both Caregiver and Provider derived state, including today.
- Selecting a person no longer resets after an unrelated care-circle mutation.
- Bedtime can cross its window boundary and reach the human-resolution question.
- Amber is reserved for unresolved `notMarked`; red is reserved for a human-confirmed `missed` event.
- Persisted data is validated before UI assumptions can turn malformed JSON into a reachable error screen.

### Verification

- `dart format --output=none --set-exit-if-changed lib test` — pass, 14 files unchanged.
- `flutter analyze` — pass, zero issues.
- `flutter test` — pass, 30 active tests; five reproducible release-capture tests intentionally skipped in the ordinary suite.
- `DOSEKEEPER_CAPTURE_SCREENSHOTS=true flutter test test/screenshot_capture_test.dart --update-goldens` — pass, five captures generated and inspected.
- `flutter build web --release` — pass; Wasm compatibility dry run also passed.
- Brand asset generator `--check` — pass for web PNGs and the multi-resolution Windows icon.
- Local Windows release build is blocked before compilation because Windows Developer Mode/symlink support is disabled; the checked-in manual Windows CI workflow is the clean-machine verification lane.

### Honest state

- v0.1 is local/offline only; no Firestore, cross-device sync, accounts, or OS notifications are claimed.
- All bundled family and medication data is fictional.
- Five headless Flutter release screenshots are committed and linked from the README.
- The GitHub Pages URL remains a deployment target until the public workflow completes successfully.

### Next

- Publish the verified commits, let GitHub CI/Pages run, verify the public Pages URL, and hand the branch to the independent Claude audit.
