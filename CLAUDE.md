# DoseKeeper — project instructions (auto-loads every session)

**First action in a fresh session: read `DESIGN.md`.** It is the contract; code follows it or amends it in writing.

## What this is
A focused Flutter product build that demonstrates state management across multiple screens through working code, persistence, and tests. Every public claim in `DESIGN.md` must remain true in the implementation.

## Rules
1. **Design before code; the DESIGN.md architecture is binding** (Riverpod, five screens, one persisted repo, web + Windows). Deviations get a written reason in DESIGN.md the same session.
2. **The state-sharing story is the product.** "Mark given on Today updates History/badges/next-due everywhere" must be real, visible, and covered by a test.
3. **Analyzer clean, tests green, no reachable red-screens.** This repository is public and should withstand close technical review. Keep commit messages readable and leave no debris.
4. **Honest labels everywhere:** seed family is fictional and labeled; app is a personal/family tool, not a medical device — no dosage advice, no drug data.
5. **Zero cost:** free tooling only (Flutter, VS Community, Vercel/GitHub Pages).
6. **Ship the guaranteed lane first:** web build working end-to-end before touching Windows desktop; Android only if everything else is done and polished.
7. Keep a short `CHANGELOG.md` per session: what changed, verification (analyze/test/run), honest state, next step.

## Division of labor
This workspace builds DoseKeeper only. Do not modify files outside this repository.
