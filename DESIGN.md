# DoseKeeper — design contract v2 (2026-07-11)
**The product vision:** a medication **care network**, not a personal tracker. The person taking the meds marks doses; everyone who cares — a parent watching a kid, an adult child watching an aging parent, a nurse or provider prepping for the weekly appointment — sees the same live truth from their own angle.

**The proof constraint:** demonstrate a real Flutter feature with state management across multiple screens or platforms. This document records the binding product decisions; public claims must be backed by running code and tests.

## Locked product decisions (2026-07-11)
1. **Named slots with internal time windows** (local time): Morning / Noon / Afternoon / Evening / Bedtime, each mapping to a window (e.g., Afternoon = 12–5pm). Schedules speak human ("Afternoon dose"), logic uses the window.
2. **Escalating reminder flow instead of auto-"missed":** early-window heads-up ("afternoon dose coming up") → late-window reminder (still unmarked) → after the window closes, the app asks THE QUESTION: "Did you take your dose and forget to mark it, or did you miss it?" — the human's answer resolves not-marked → taken(late-marked) or missed. v0.1 = in-app banners/prompts only (no OS push, per non-goals). A labeled **demo clock** control lets a viewer move the time of day to see the escalation live.
3. **Names: Care Circle + Person.**

## The design invariant
Three distinct dose states, never conflated: **TAKEN · MISSED · NOT MARKED.** "Did you forget to take it, or forget to mark it?" is a different conversation than "you missed it" — the provider view exists to have that conversation. Most med apps collapse these; DoseKeeper doesn't.

## Roles = perspectives on one source of truth
1. **Patient view** — big, dead-simple: today's doses, one tap to mark taken. (Designed for an elderly parent or a kid.)
2. **Caregiver dashboard** — at-a-glance peace of mind: per-person adherence today/this week, with urgent not-marked doses and human-confirmed missed doses surfaced first. Resolving "missed" never makes an attention item disappear.
3. **Provider/appointment view** — a live, read-only Today panel plus an adherence timeline for a selectable date range: taken/missed/not-marked per dose, built for the "I see you marked this Tuesday… was Thursday a miss or a forgot-to-mark?" appointment conversation.
Plus: **Care Circle** (people, meds, schedules) and **Settings/About** (demo controls, persistence state, limitations, reset).

The state-sharing spine: marking a dose in the Patient view instantly updates the Caregiver dashboard, the Provider Today panel, and every badge — because every screen watches the same Riverpod providers. Nothing passes state to anything. This is proven through widget-level taps and cross-view assertions, not only notifier unit tests.

## Scope ruling (2026-07-11)
- **v0.1:** ONE app, all role views live, one shared state layer (Riverpod), local persistence, and a role-switcher in the UI. Fully offline.
- **Future stretch:** real cross-device live sync through a repository such as Firebase Firestore (anonymous auth + family join-code; streams feed the same providers). This is intentionally not implemented or claimed in v0.1.
- **Architecture that makes both true without UI rework:** all data access sits behind one repository interface with initial `load`, ordered `save`, and a `watch` stream for remote snapshots. `LocalRepo` (v0.1, JSON/shared_preferences) has an empty remote stream; a future `FirestoreRepo` supplies the stream. The repository is injected once at bootstrap and screens do not know which implementation is active.

## Architecture (binding)
- **State: Riverpod** — providers: `careCircleProvider` (people, meds, schedules, dose events — the persisted store), `todayDosesProvider(person)` (derived), `pendingQuestionsProvider(person)` (previous-day rollover), `adherenceProvider(person, range)` (derived), selected-person/range providers, a reactive local clock, persistence status, and settings/demo controls. UI watches; notifier mutations queue repository saves; derived state recomputes.
- Dose event model: schedule slot × date → state ∈ {taken(recordedAt), missed(explicit, recordedAt), notMarked(default)}. `recordedAt` is when the human recorded the answer, never a claim about ingestion time. Missed is human-confirmed, never auto-equated with unmarked.
- Schedules have an effective-from date so absence before known coverage is "not scheduled," not fabricated non-adherence.
- **Clock/rollover:** real local time refreshes while the app remains open. The labeled demo clock can detach from real time and includes an explicit `+1 day` position so Bedtime crosses its 24:00 boundary. Unresolved previous-day doses remain answerable after midnight.
- **Corrections:** a human can correct taken/missed answers or clear an event back to not-marked. Every correction is another explicit human action and persists through the same repository path.
- **Platforms:** web (required, deployed live) + Windows desktop (bonus). Five+ screens already satisfies "screens or platforms."
- **Seed data:** fictional care circle ("load example family": grandma + kid, 3 meds, 10 days of mixed history incl. not-marked days) — labeled fictional.
- **Non-goals:** real accounts/PHI, OS push notifications, iOS build, drug databases/interactions, medical advice. This is a coordination tool, not a medical device — label it so.

## Quality bar
`flutter analyze` clean · `flutter test` green incl. the cross-role state invariant (mark taken via patient provider → caregiver + provider views reflect it) and the three-state integrity test (unmarked ≠ missed) · no reachable red-screens · README with screenshots + architecture note · public repo (`Xyloth/dosekeeper`) · live web deploy ($0: Vercel static or GitHub Pages) · 60-second demo script.

## Build mode (binding for this project)
Decision-led and reviewable. Product naming, state, and UX choices are recorded as they are made, and the code remains understandable enough for a maintainer to explain each layer. No unreviewed autonomous runs.

## Delivery sequence
1. Environment: Flutter SDK stable + `flutter doctor` (web is the guaranteed lane).
2. Data model + repository interface together.
3. Providers + patient view (the money interaction) → caregiver dashboard → provider timeline → people/meds/settings.
4. Seed data, tests, analyze clean, deploy web, repo public.
5. Exercise the full interaction flow, capture screenshots, publish the verified web build, and consider synchronized persistence only as a later extension.
