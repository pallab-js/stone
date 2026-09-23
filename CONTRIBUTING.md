# Contributing to PaashERP

Thanks for contributing! PaashERP is MIT-licensed, local-first and dependency-light.
Please keep every contribution aligned with that.

## Ground rules

- **Local-first & offline.** Nothing may require a network connection to function.
- **No auth, no cloud, no telemetry.** This is a single-admin desktop app.
- **Single-line-of-business clarity.** A stone crusher ERP — avoid scope creep
  into general accounting or payroll.
- **Money = paise (`Int64`), quantities = kg (`Int64`).** Never floats for money
  or inventory math.

## Before you start

1. Open an issue describing the change (feature / bug / question).
2. Wait for a maintainer to acknowledge and tag it with a milestone (P0–P8).
3. Fork, branch (`feat/xyz`, `fix/xyz`), implement.

## Definition of done

- Code builds with `xcodegen generate && xcodebuild -scheme PaashERP build`
- New logic has unit tests (services: GST math, stock movement, invoicing, formatting)
- UI follows `Sources/DesignSystem` tokens — no ad-hoc colors, fonts, or spacing
- No new external dependencies without discussion in the issue
- `swiftformat`/`swiftlint` clean if they are added to the repo
- Screenshots in the PR description when the change affects UI

## Commit style

Concise, imperative, lowercase-ish: `add product rate history`, `fix invoice
series counter race`, `seed demo production data`. PRs squash cleanly.

## Getting help

Open a discussion in the repo or tag a maintainer on the issue. This is a
small, friendly project — say hi.