# PaashERP — Stone Crusher ERP

A **local-first, offline-first ERP** for a stone crusher business unit in India.
Built in **Swift + SwiftUI** for **macOS 15+**, with **SQLite (GRDB)** as a
single-file database. Single admin user, no cloud, no auth, no server.

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platform](https://img.shields.io/badge/macOS-15%2B-black.svg)
![License](https://img.shields.io/badge/License-MIT-blue.svg)

> **Status: MVP complete.** All core modules implemented: dashboard with live
> charts, production, GST sales & invoicing (PDF export), payments, purchases,
> stock with adjustments, reports with CSV export, and masters. 47 unit tests
> passing — schema/seeder invariants, formatting, PDF/CSV exports, and a
> business-workflow suite that exercises production batches, GST invoice math
> (CGST/SGST/IGST), invoice numbering, stock deduction & reversal, invoice
> cancellation, payments, receivables aging, stock valuation, and the Reports
> KPIs end-to-end.

---

## Why PaashERP?

A crusher unit runs on: quarry royalty, plant production, truck dispatch,
weighbridge slips, GST tax invoices, diesel/electricity bills, daily-wage
labour and dozens of customers on credit. Most units still run this on
Excel + a paper diary because every "cloud ERP" needs internet and training.

PaashERP is the opposite: a native macOS app that **works fully offline**, keeps
every record in **one local SQLite file**, and gives the owner a single
dashboard showing *what was crushed, what was sold, what's in the yard, and
who owes what* — at a glance.

## Features (MVP)

- 📊 **Central dashboard** — KPIs and live charts (Swift Charts)
- 🏭 **Production** — batches, shifts, machine hours, diesel, product-wise tonnes
- 🚚 **Sales & dispatch** — trucks, weighbridge net weight, GST tax invoices (CGST/SGST/IGST, HSN)
- 💰 **Payments** — cash / UPI / cheque / transfer, advances, receivables
- 🛒 **Purchases & expenses** — diesel, electricity, royalty, parts, labour, misc
- 🏗 **Stock** — stock-in/out, adjustments, wastage, stock statement & valuation
- 📋 **Reports** — daily production/sales, GST summary, receivables aging, mini P&L (CSV export)
- 💾 **Local-first** — single-file SQLite DB, one-click backup
- 🎨 **Uniform enterprise design system** — one consistent theme across every screen

## Roadmap

| Phase | Scope | Status |
|-------|-------|--------|
| P0 | Project skeleton, DB schema + migrations, design system, app shell, demo data | ✅ Done |
| P1 | Masters — Products, Customers, Suppliers, Vehicles | ✅ Done |
| P2 | Production module | ✅ Done |
| P3 | Sales, GST invoicing, payments | ✅ Done |
| P4 | Purchases & expenses | ✅ Done |
| P5 | Stock & adjustments | ✅ Done |
| P6 | Dashboard & analytics (live KPIs + charts) | ✅ Done |
| P7 | Reports, mini P&L, PDF & CSV export | ✅ Done |
| P8 | Polish, backups, tests, handover | 🧪 Verified — 47 tests green |

## Tech stack

- **Language:** Swift 6 (strict concurrency)
- **UI:** SwiftUI — `NavigationSplitView`, `Swift Charts`
- **Persistence:** SQLite via [GRDB.swift](https://github.com/groue/GRDB.swift)
  with versioned migrations
- **Money:** stored as paise (`Int64`), quantities stored as kilograms (`Int64`)
- **Formatting:** Indian digit grouping (₹1,23,456.00), tonnes with 2 decimals

## Build & run

Requirements: **Xcode 15+ on macOS 13+** (built against Xcode 27 / macOS 27).

Uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the project
(install with `brew install xcodegen`). The `.xcodeproj` is checked in for
convenience but is fully reproducible from `project.yml` — regenerate it
anytime with `xcodegen generate`.

```sh
brew install xcodegen
xcodegen generate          # creates PaashERP.xcodeproj
open PaashERP.xcodeproj    # ⇧⌘R to run
```

Or build from the command line:

```sh
xcodegen generate
xcodebuild -scheme PaashERP -configuration Debug build
```

### First launch

On first launch the app creates `~/Library/Application Support/PaashERP/`
and seeds **realistic demo data** (≈30 days of a modelled crushing unit) so
every screen is instantly demonstrable. Clear it anytime from
**System → Reset database** to start fresh.

## Project layout

```
Sources/
  App/          App entry point, app state, root shell
  DesignSystem/ Color/type tokens + reusable enterprise components
  Database/     GRDB store, migrations, demo seeder
  Models/       GRDB record types (one file per entity)
  Support/      Formatting (₹/tonnes), backup, helpers
  Views/        Dashboard, Production, Sales, Purchases, Stock, Masters, Reports
Tests/          XCTest unit tests (services, formatting)
```

## Contributing

MIT-licensed and open source. Bug reports and feature requests via GitHub
issues — see `CONTRIBUTING.md`. No auth, no cloud, no telemetry: keep it
local-first and dependency-light.

## License

[MIT](LICENSE)