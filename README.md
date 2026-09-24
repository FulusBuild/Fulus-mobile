# Fulus

**Business management for West African small shops — built for a phone, and built to work without one bar of signal.**

---

## Overview

Fulus is a mobile-first business management app for small shop owners across West Africa — the kind of business that runs on a single Android phone, keeps its books in a notebook, and can't afford a stockout because a network connection dropped mid-sale.

Every core workflow — making a sale, adjusting stock, recording an expense, tracking a customer's credit — runs entirely on the device, against a local database, with no server round-trip required to complete the action. An internet connection is useful, never mandatory: when one is available, Fulus can synchronize with a central business backend so a shop's data is backed up and viewable beyond the till. When it isn't, the shop keeps running exactly as before.

Fulus is designed to be understood in under a minute by someone who has never used a business app before, and to keep working through the conditions — patchy data, shared devices, intermittent power — that most software quietly assumes away.

## Project Status

**The core app — the Business Engine and the full user interface built against it — is complete.** Home, Sell, Stock, Money, and the More section (Employees, Reports, Settings, Backup) are all built, routed, and reachable today. Every core workflow — selling, stock and catalog management, customer credit, finance tracking, employee records, receipt printing, backup, and optional synchronization — runs end to end, on-device.

Current work is production-readiness refinement: accessibility, data-integrity hardening, and the remaining items tracked ahead of a wider commercial release.

## Key Features

**Sales & Point of Sale**
Cart-based checkout with per-item and whole-cart discounts, multiple payment methods and split payments, quick sale for one-off items not yet in the catalog, and full returns handling.

**Inventory & Catalog**
Add and edit products directly from the app, or bring in an existing catalog in bulk via CSV import. Stock-in, stock-out, and adjustment tracking with a full movement history, categories, suppliers, and per-location stock levels for shops operating across more than one site.

**Customers**
Customer records with a running credit ledger — track what's owed, record payments against it, and see a customer's history at a glance.

**Finance**
Income and expense tracking with categorization, supplier ledgers, tax remittance records, and profit/cash-flow reporting.

**Employees**
Staff roster, attendance, and leave tracking. An owner can set up a login for any staff member directly from their own account, and an owner-approval PIN system lets staff operate the till under supervision without full account access.

**Reports & Insights**
Sales, inventory, and finance reporting with CSV and PDF export.

**Receipt Printing**
Direct ESC/POS printing to paired Bluetooth or USB thermal printers — no separate print server required.

**Backup & Restore**
On-device backup and restore of the full local database.

**Sync — optional, never required**
When connectivity is available and sync is turned on, Fulus reconciles with a central backend in the background, with automatic retry, conflict detection, and Android WorkManager scheduling. Foreground sync reacts to mutations, connectivity changes, resume, and periodic retry; Android WorkManager provides an OS-scheduled recovery path when the Flutter process has been suspended or terminated. Background execution is opportunistic because Android controls when scheduled work runs, so this is not a permanently open network connection. The app is fully functional with sync permanently off.

## Architecture

### Offline-First Philosophy

Fulus is built local-first, not local-as-fallback. Every write — a sale, a stock adjustment, an expense entry — is committed to the on-device database immediately and only *afterward*, if sync is enabled and a connection exists, queued for reconciliation with the backend. The app never blocks a user-facing action on a network call. Authentication follows the same principle: sign-in is verified against a local, securely hashed credential store, not a remote login endpoint, so the app is usable from the very first launch on a device that has never been online.

### Layered Architecture

Fulus follows a clean, layered structure that keeps business rules independent of both the database and the UI:

```
┌─────────────────────────────────────────┐
│              Presentation                │  Screens, widgets — Flutter/Riverpod
├─────────────────────────────────────────┤
│                 Domain                   │  Entities, repository interfaces,
│                                           │  business rules (the Business Engine)
├─────────────────────────────────────────┤
│                  Data                    │  Repository implementations,
│                                           │  local database, remote sync client
└─────────────────────────────────────────┘
```

The domain layer has no dependency on Flutter, on the local database implementation, or on any networking code — it can be reasoned about, and tested, entirely on its own terms.

### The Business Engine

Fulus's business logic — the rules that decide what a valid sale looks like, how stock moves, how customer credit accrues, what a supervisor's approval PIN unlocks — is written entirely in native Dart. There is no server-side process a phone has to reach in order to enforce these rules; the same engine that runs the checkout flow runs identically whether the device is online or has never seen a network in its life.

## Technology Stack

| Layer | Technology |
|---|---|
| Framework | Flutter / Dart |
| Local database | Drift (typed SQL) over SQLite |
| State management & DI | Riverpod |
| Navigation | go_router |
| Networking (optional sync) | Dio, over HTTP(S) |
| Connectivity detection | connectivity_plus |
| Security | Argon2id password/PIN hashing |
| Background sync scheduling | WorkManager |
| Receipt printing | ESC/POS over Bluetooth and USB |
| Barcode scanning | On-device camera-based scanning |

## Folder Structure

```
lib/
├── app/                    # App entry point, DI wiring, navigation, bootstrap
├── core/                   # Cross-cutting concerns
│   ├── business_engine/    # Core, entity-spanning business rules
│   ├── config/             # Environment configuration
│   ├── errors/              # Typed failure/exception hierarchy
│   ├── export/              # CSV/PDF export services
│   ├── notifications/       # In-app notification delivery
│   ├── security/            # Password and PIN hashing
│   ├── theme/                # Design tokens and app theming
│   └── utils/                 # Shared low-level helpers (e.g. CSV parsing)
├── data/
│   ├── local/database/      # Drift schema, migrations, database lifecycle
│   ├── remote/               # Optional backend API client and endpoints
│   └── repositories/         # Repository implementations
├── device_services/          # Camera, barcode scanning, printer discovery & printing
├── domain/
│   ├── entities/              # Core business data types
│   ├── repositories/          # Repository interfaces
│   └── usecases/              # Business Engine action classes
├── features/                  # Screens and UI, organized by feature area
│   ├── home/
│   ├── sell/
│   ├── stock/
│   ├── money/
│   └── more/
└── sync/                       # Sync engine, per-entity handlers, retry/conflict logic, sync queue
```

## Database

Fulus stores all data locally using Drift over SQLite — a fully typed, compile-time-checked schema rather than raw SQL strings. The local database is the single source of truth on the device; nothing about the app's core functionality depends on a remote database being reachable.

The schema covers the full business domain: products, stock levels and stock movements, sales and sale items, customers and their credit ledgers, suppliers, expenses and income, employees and attendance, cash drawer shifts, and more — each table designed to mirror the equivalent server-side concept where Fulus operates alongside a central backend, while staying independently useful where it doesn't.

Schema changes are handled through versioned, incremental migrations, so existing installs upgrade in place without data loss.

## Synchronization

Synchronization is strictly optional and off by default. When enabled, Fulus queues changes locally as they happen and reconciles them with a central backend opportunistically — whenever connectivity is available, without blocking or slowing down the app in the meantime. Each business-data type that supports sync has a dedicated handler responsible for translating between the local and remote representations, so sync logic for one type of record can evolve independently of the others. A failed sync backs off with increasing delay rather than retrying immediately, and a change that conflicts with one made elsewhere is flagged rather than silently overwritten in either direction.

A shop that never turns sync on loses nothing from the core experience — sync exists to layer on cross-device visibility and backup, not to gate day-to-day use.

### Background Sync Runtime

Android background sync is implemented in `lib/sync/background_sync.dart`. The scheduler registers one unique 15-minute periodic task when Cloud Sync is enabled and cancels it when sync is disabled. The worker boots the same production sync stack used by the foreground runtime, including authentication restoration, device registration/readiness, durable outbox draining, pull/canonical reconciliation, and stale-cursor recovery. A short SQLite lease in `sync_runtime_leases` serializes foreground and background execution; the lease renews while active and expires after process death so a later runtime can recover automatically.

The implementation intentionally does not claim exact 15-minute execution or an always-open connection. Android may defer scheduled work according to OS resource and battery policy. The release gate still includes physical Android validation after app termination/backgrounding.

## Backup & Restore

Fulus supports full on-device backup and restore of the local database independent of network connectivity, so a shop's data can be protected without depending on cloud sync being configured or reachable.

## Receipt Printing

Fulus prints directly to ESC/POS-compatible thermal printers over Bluetooth or USB, with no intermediary print server or desktop pairing step required — pair a printer once from within the app and it's available for every sale going forward.

## Getting Started

### Prerequisites

- Flutter SDK (stable channel)
- Dart SDK (bundled with Flutter)
- Android SDK / Xcode, depending on target platform
- A physical device or emulator/simulator for testing hardware-dependent features (camera, Bluetooth/USB printing) — these will not exercise correctly on most emulators

### Installation

```bash
git clone <repository-url>
cd fulus
flutter pub get
```

### Running the App

Generated code (Drift's database layer and JSON serialization) isn't checked into this repository — build it first, or nothing below will compile:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Then run static analysis and the test suite — worth doing on every fresh checkout, not just the first one:

```bash
flutter analyze
flutter test
```

And run the app itself:

```bash
flutter run
```

### Building for Release

```bash
# Android
flutter build apk --release
# or, for a smaller distributable:
flutter build appbundle --release

# iOS
flutter build ios --release
```

## Roadmap

**Near-term priorities:**
- Round out the rest of Settings beyond what's built today
- A cross-device employee invite flow (QR-code based) for shops running more than one device — today, an owner sets up a staff login from the same device that staff member will use

**Further out:**
- Localization into additional languages spoken across the target market
- Multi-location transfer support
- Expanded reporting and insights

## Contributing

Contributions are welcome. Before submitting a change:

1. Run `dart run build_runner build --delete-conflicting-outputs`, then `flutter analyze` and `flutter test`, and confirm all three pass cleanly.
2. Match the existing layered architecture — business logic belongs in `domain/`, not in UI code.
3. Add or update tests alongside any change to `data/` or `domain/`.
4. Keep commits focused and describe the *business* reasoning behind a change, not just the code change itself.

## License

Proprietary. All rights reserved, unless otherwise stated by the project owner.
