# Rivero — Gap Analysis & Implementation Readiness Report
**Document Code:** `RIVERO-GAP-001`  
**Status:** Under Owner Review  
**Date:** November 2026  
**Target Application:** Rivero (Flutter / Android & iOS)  
**Author:** parthivkumarnikku <parthivkumarnikku@gmail.com>

---

## Executive Summary

Rivero is conceived as a local-first, privacy-respecting personal financial management system built upon a **salary-root and waterfall-allocation** architecture. Unlike conventional expense trackers that treat financial inflows and outflows as flat transaction logs, Rivero models how real personal liquidity flows: from primary income sources, cascading through planned buckets (Expenses, Investments, Savings, Custom purposes), balancing revolving liabilities (Credit Cards), and servicing automated commitments (UPI Autopay & e-NACH mandates).

This document fulfills the directive of the **Rivero Master Context Addendum**. It provides an exhaustive gap analysis comparing the 20-page architecture research PDF, the approved `ARCHITECTURE.md`, the Phase 0/1 implementation baseline, and real-world engineering realities across Android and iOS.

---

## 1. Existing Architecture & Implementation Summary

### 1.1 What Has Been Implemented (Phase 0 & Phase 1 — ISSUE-001)
- **Local Environment & Isolation:**
  - Dedicated workspace at `~/rivero-workspace/` with strict boundary separation between `.reference_repos/`, workspace guidance (`AGENTS.md`, `ARCHITECTURE.md`), and the clean repository `rivero/`.
  - Zero external Git remotes (`git remote -v` is empty).
  - Author identity locked to `parthivkumarnikku <parthivkumarnikku@gmail.com>`.
  - Comprehensive `.gitignore` (172 rules) and `.git/info/exclude` (50 rules) strictly omitting AI transcripts, agent metadata, `.env`, keys, and databases.
  - Telemetry and analytics disabled at the SDK level.
- **Project Baseline & Design System:**
  - Flutter 3.50.0 / Dart 3.14.0 foundation.
  - Dependencies installed and locked: `flutter_riverpod`, `riverpod_annotation`, `flutter_animate`, `sprung`, `animated_flip_counter`, `flutter_card_swiper`, `flutter_secure_storage`, `app_links`, `google_fonts`, `intl`, `very_good_analysis`.
  - Reusable tokens (`RiveroColors`, `RiveroSpacing`, `RiveroRadii`, `RiveroTypography`, `RiveroTheme`) implementing the Slice-inspired dark palette:
    - Pitch Background: `#08080C`, Surface: `#12121A`, Elevated Surface: `#1A1A26`
    - Hierarchy Accents: Salary Root (`#F59E0B`), Expense (`#8B5CF6`), Investment (`#10B981`), Savings (`#06B6D4`), Mandate Warning (`#F43F5E`)
    - Typography pairings: Plus Jakarta Sans (Display/Counters), Inter (UI), JetBrains Mono (Masks/Timestamps).
- **Domain Foundation & Utilities:**
  - `AccountRole` enumeration (`salaryRoot`, `expense`, `investment`, `savings`, `custom`, `liabilityCc`, `virtualWallet`) with accent and code mappings.
  - `CurrencyFormatter` with integer minor units (paise in INR) enforcing zero floating-point arithmetic for financial values.
  - Reusable design components: `RiveroCard`, `RiveroButton`, `RoleBadge`, `FinancialAmountText`, `RiveroAppBar`.
  - Interactive foundation showcase screen in `lib/main.dart` demonstrating Safe-to-Spend counter, live daily pace metric, bucket overview, and privacy toggle.
  - Complete test harness (19/19 passing tests, 0 analysis warnings, clean formatting).

### 1.2 What Was Planned in Architecture Roadmap (Phase 2 to 10)
- **Phase 2 (ISSUE-002):** Drift + SQLCipher encrypted database, schema, and key management.
- **Phase 3 (ISSUE-003):** Financial allocation engine (WaterfallAllocator, Safe-to-Spend, daily pace).
- **Phase 4 (ISSUE-004):** Ingestion & parsing (TRAI DLT headers, bank notifications, regex extraction, multi-channel dedup).
- **Phase 5 (ISSUE-005):** Reconciliation (self-transfer matching, investment routing).
- **Phase 6 (ISSUE-006):** Home experience (hero counter, bucket swiper, triage card swiper).
- **Phase 7 (ISSUE-007):** Recurring commitments (UPI mandates, e-NACH lifecycle, liquidity alerts).
- **Phase 8 (ISSUE-008):** Platform bridges (Android NotificationListener, iOS Shortcuts/deep-links).
- **Phase 9 (ISSUE-009):** Advanced reconciliation (CC settlement, refund matching, split-bills, drift detection).
- **Phase 10 (ISSUE-010):** Experimental labs (SLM, Monte Carlo runway simulator).

---

## 2. Gap Register & Severity Classification

| Gap ID | Area | Existing Decision / Spec | Missing Requirement | Risk | Recommendation | Priority | Dependency | Approval |
|---|---|---|---|---|---|---|---|---|
| **GAP-01** | Financial Ledger | Single transaction table with debit/credit flags. | Immutable double-entry transaction legs and explicit transaction lifecycle states (`DETECTED` -> `PARSED` -> `NEEDS_REVIEW` -> `CONFIRMED` -> `RECONCILED` -> `REVERSED`). | Erroneous balance mutations, lost audit trail on user correction, corrupt ledger. | Design a two-tiered ledger: `IngestionEvents` (raw immutable logs) and `LedgerEntries` with explicit parent-child transaction legs. | **P0** | ISSUE-002, ISSUE-011 | Required |
| **GAP-02** | Account Hierarchy | Fixed roles where each bucket is modeled identically. | Distinction between physical bank accounts (custodial) and virtual buckets (budget allocations). Handling multiple physical accounts per role. | Virtual buckets creating fictitious money or duplicating physical balances; inability to model a user with 2 salary accounts or 3 credit cards. | Separate `PhysicalAccounts` (actual balance tracking) from `AllocationBuckets` (virtual budget targets mapped to physical accounts). | **P0** | ISSUE-002, ISSUE-012 | Required |
| **GAP-03** | Waterfall Allocation | Fixed percentage / amount distribution on salary credit. | Handling partial salary credits, bonuses, mid-cycle rule changes, negative bucket balances, and unallocated spillover. | Allocation failures when salary deviates from expected amount; negative bucket lockups; confusing virtual allocation with physical bank transfers. | Implement a stateful `AllocationPlan` with explicit priority watermarking, spillover routing, and manual override checkpoints. Never imply bank transfers occurred. | **P0** | ISSUE-003, ISSUE-011 | Required |
| **GAP-04** | Safe-to-Spend Formula | Static formula: `STS = Expense Balance - Upcoming Mandates - Unsettled Reimbursements`. | Handling stale balances, pending transactions, credit card liability settlement reservations, and reliability scoring. | False sense of liquidity leading to account overdrafts or missed loan/mandate auto-debits. | Introduce dynamic Safe-to-Spend with a confidence indicator (Stale / Estimated / Verified) and explicit breakdown drawer. | **P0** | ISSUE-003, ISSUE-006 | Required |
| **GAP-05** | Android Ingestion Feasibility | Assumed NotificationListenerService captures all financial events silently. | Handling OEM battery savers (MIUI, ColorOS, OneUI), notification redaction on lock screen, notification grouping, and Play Store policy vs FOSS build. | Silent ingestion failure on real user devices; app rejection if SMS permissions are requested. | Implement Android NotificationListener with foreground keep-alive / unmetered battery guidance, zero `READ_SMS` dependency, and explicit diagnostics screen. | **P0** | ISSUE-004, ISSUE-008, ISSUE-013 | Required |
| **GAP-06** | iOS Ingestion Feasibility | Assumed iOS Shortcuts can silently forward transactions via `rivero://ingest`. | iOS cannot silently run Shortcuts without user confirmation for SMS/notifications; deep-links require app to open or use background AppIntents with strict execution limits. | High friction making iOS ingestion unusable or completely broken for passive tracking. | Create a first-class manual transaction workflow, Share Sheet parser, and AppIntents prototype with honest platform limitation disclosures. | **P0** | ISSUE-008, ISSUE-013 | Required |
| **GAP-07** | Data Recovery & Backup | Local-first encrypted database via SQLCipher. | Device loss or app uninstall causes permanent data loss; no recovery pathway. | Catastrophic data loss when users switch phones or reinstall app. | Implement offline encrypted backup (AES-GCM / Argon2id passphrase) exporting to user-selected file location with integrity verification. | **P0** | ISSUE-002, ISSUE-014 | Required |
| **GAP-08** | Mandate Lifecycle | Basic state machine with pre-debit alerts. | Pre-debit notification does not equal execution. Handling variable/max amount mandates, mandate modification, and missed execution alerts. | Double debit deductions or unexpected liquidity deficit when variable mandate (e.g. utility bill) executes at max cap. | Split mandate tracking into `MandateAgreement` (fixed vs maximum cap) and `MandateExecution` (actual debit reconciliation). | **P1** | ISSUE-007 | Required |
| **GAP-09** | Investment Domain | INVESTMENT bucket treated as a regular expense bucket. | Investment cashflows (SIP, stocks, PPF) are asset transfers, not consumable expenses; market valuation cannot be assumed without live feeds. | Skewing net worth, treating investments as consumed expenses, false portfolio tracking. | Model Investment contributions as asset transfers. Track cashflows accurately without claiming unverified portfolio valuations. | **P1** | ISSUE-003, ISSUE-005 | Not required |
| **GAP-10** | Deduplication & Multi-Channel | Scoring deduplicator using ±180-second window and amount. | Matching SMS vs push notification vs user-entered transaction; ambiguous match resolution. | False merges corrupting legitimate identical-amount transactions (e.g., two ₹500 chai/groceries in 3 minutes). | Multi-key deduplication: UTR/RRN priority, account mask verification, and interactive user triage for ambiguous collisions. | **P1** | ISSUE-004, ISSUE-005 | Not required |
| **GAP-11** | UX Beyond Home Screen | Heavy emphasis on three-second glance home screen. | Missing specifications for onboarding, account registration, manual transaction entry, mandate management, search, and settings. | Incomplete application that cannot be configured or operated manually when automation fails. | Design and document the complete 17-screen user journey, prioritizing manual entry and triage flows. | **P1** | ISSUE-006, ISSUE-015 | Required |
| **GAP-12** | Key Management & Security | Key stored in flutter_secure_storage. | Android Keystore / iOS Keychain behavior on app reinstallation; lack of biometric app-lock. | Database inaccessible after OS backup restore, or sensitive financial data accessible without device authentication. | Implement key derivation architecture with optional biometric / PIN app lock and clear key-loss recovery warnings. | **P1** | ISSUE-002, ISSUE-016 | Required |

---

## 3. Detailed Technical Findings

### 3.1 Financial Domain & Ledger Integrity
- **Physical Accounts vs Virtual Buckets:**
  In a real personal finance setup, a user might receive salary into an **HDFC Savings Account** (`PhysicalAccount`). From that single physical account, they want to allocate:
  - ₹40,000 to **Rent & Living** (`EXPENSE` bucket)
  - ₹30,000 to **Mutual Funds** (`INVESTMENT` bucket)
  - ₹20,000 to **Emergency Fund** (`SAVINGS` bucket)
  The money has **not** moved to separate bank accounts; it sits in HDFC. If the app treats buckets as separate accounts, it risks creating fictitious transfers. Conversely, when the user spends ₹5,000 at a grocery store with their HDFC debit card, the system must debit both the **HDFC Physical Account** and the **Expense Bucket**.
- **The Ledger Double-Entry Model:**
  Every transaction should have:
  - An originating event (`RawIngestionLog` or manual user input).
  - Transaction state: `DETECTED` -> `PARSED` -> `NEEDS_REVIEW` -> `CONFIRMED` -> `RECONCILED` -> `REVERSED`.
  - Transaction legs: e.g. Credit Card payment of ₹15,000 debits HDFC Bank (`PhysicalAccount`), credits ICICI Sapphiro (`LiabilityAccount`), and has **zero net expense impact** (the expense was already recognized at the time of purchase).

### 3.2 Platform Feasibility Findings

#### 3.2.1 Android Feasibility
- **NotificationListenerService Capabilities:**
  - Android allows an application with `BIND_NOTIFICATION_LISTENER_SERVICE` to intercept notifications posted by other apps (e.g., GPay, PhonePe, Paytm, HDFC MobileBanking, ICICI iMobile, SMS apps).
  - **Permission Gate:** The user must be redirected to `android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS` and manually toggle access. This cannot be granted silently.
  - **Lock Screen Redaction:** If the user has "Hide sensitive notification content" enabled in Android OS settings, notifications received while locked will contain empty title/body until unlocked. The listener must buffer notification keys and query active notifications upon unlock.
  - **OEM Battery Restrictions:** Xiaomi (MIUI/HyperOS), Samsung (OneUI), and OnePlus (OxygenOS) aggressively kill background services. Rivero must provide an in-app "Battery Optimization Exemption" wizard directing users to disable power-saving restrictions for the service.
  - **Play Store Policy:** Google Play strictly restricts `READ_SMS` and `RECEIVE_SMS` to default SMS handler apps. **Rivero must NOT use READ_SMS**. Relying on NotificationListener keeps Rivero 100% compliant with Google Play policies.

#### 3.2.2 iOS Feasibility
- **SMS & Notification Ingestion Limitations:**
  - iOS provides **zero public APIs** for third-party apps to passively read SMS messages or intercept system notifications.
  - **Shortcuts Automation:** iOS Shortcuts app allows personal automations triggered by "When I receive a message containing...". However:
    1. The user must manually configure the Shortcut on their device (high friction).
    2. In earlier iOS versions, message automations required tapping a notification to confirm running the shortcut. In iOS 17+, "Run Immediately" is supported for message automations, but setup requires precise user action.
    3. Shortcuts can pass text to Rivero via custom URL scheme (`rivero://ingest?content=...`) or via AppIntents / App Groups.
- **Architectural Conclusion for iOS:**
  - Rivero on iOS **cannot** rely on passive background ingestion.
  - Rivero must provide a first-class **Manual Entry** flow, a **Share Sheet extension** (allowing users to share bank SMS/email text directly to Rivero), and an optional guided Shortcuts configuration.
  - The UI must honestly inform iOS users of platform boundaries.

### 3.3 Security, Privacy & Recovery Findings
- **SQLCipher Key Management:**
  - `flutter_secure_storage` stores keys in the Android Keystore (encrypted via AES-GCM) and iOS Keychain (protected with `kSecAttrAccessibleAfterFirstUnlock`).
  - **Reinstall Risk:** On Android, if `android:allowBackup="true"` is set, the encrypted database might be restored on a new device, but the Keystore key is hardware-bound and **not restored**, rendering the database permanently unreadable.
  - **Fix:** Set `android:allowBackup="false"` or implement explicit database backup/restore workflows with a user-controlled passphrase.

---

## 4. Proposed Extended Issue Roadmap

To address all identified gaps while preserving the original foundation, the roadmap is updated as follows:

```
[Phase 0: Environment Audit & Setup] (COMPLETED)
     ↓
[Phase 1: Project Foundation & Design System (ISSUE-001)] (COMPLETED)
     ↓
[GAP ANALYSIS & ARCHITECTURE APPROVAL] (CURRENT STAGE)
     ↓
[Phase 2: Encrypted Storage & Ledger Schema (ISSUE-002 + ISSUE-011)]
     ├── PhysicalAccounts vs VirtualBuckets tables
     ├── Immutable IngestionLog & LedgerEntry schema
     └── SQLCipher + SecureStorage key lifecycle
     ↓
[Phase 3: Financial Engine & Invariants (ISSUE-003)]
     ├── Salary-Root WaterfallAllocator
     ├── Dynamic Safe-to-Spend & Daily Pace
     └── Invariant test harness (Double-entry balance zero-sum)
     ↓
[Phase 4: Ingestion Pipeline & Parser Engine (ISSUE-004)]
     ├── TRAI DLT header validation
     ├── Indian bank & UPI regex parsing
     ├── Multi-channel scoring deduplicator
     └── Quarantine review queue (EC-10)
     ↓
[Phase 5: Financial Reconciliation (ISSUE-005 + ISSUE-012)]
     ├── Self-transfer detection
     ├── Credit Card liability settlement
     ├── Investment routing
     └── Balance drift reconciliation
     ↓
[Phase 6: Core UX & Triage Workflows (ISSUE-006 + ISSUE-015)]
     ├── Hero Safe-to-Spend counter
     ├── Bucket cards & allocation progress
     ├── Transaction triage card swiper
     └── Manual transaction creation & account onboarding
     ↓
[Phase 7: Mandates & Commitments (ISSUE-007)]
     ├── UPI Autopay / e-NACH state machine
     ├── Pre-debit vs execution tracking
     └── Liquidity deficit alerts
     ↓
[Phase 8: Platform Integrations & Bridges (ISSUE-008 + ISSUE-013)]
     ├── Android NotificationListenerService bridge
     ├── iOS Shortcuts / Deep-link receiver & Share Sheet
     └── Platform capability diagnostic screen
     ↓
[Phase 9: Backup, Recovery & Privacy Controls (ISSUE-014 + ISSUE-016)]
     ├── Encrypted offline backup (passphrase-protected)
     ├── Data export & raw log scrubbing
     └── Threat model verification
     ↓
[Phase 10: Experimental Labs (ISSUE-010)]
     ├── Monte Carlo runway simulation
     └── Isolated feature flags
```

---

## 5. Minimum Viable Product (MVP) Boundary

To ensure Rivero is delivered with high financial reliability, the MVP boundary is explicitly defined:

### In MVP Scope:
1. **Account Hierarchy & Buckets:**
   - Physical accounts (HDFC, ICICI, Cash, etc.) with opening balances.
   - Salary Root account definition.
   - Virtual buckets: Expense, Investment, Savings, Custom, Credit Card Liability.
2. **Waterfall Allocation Engine:**
   - Automatic allocation upon salary credit.
   - Safe-to-Spend live calculation with daily pace.
   - Invariant testing ensuring virtual buckets never invent money.
3. **Local Encrypted Storage:**
   - SQLCipher encrypted database with secure key lifecycle.
   - Complete local privacy (zero telemetry, zero cloud calls).
4. **Transaction Ingestion (Android & Manual):**
   - Android NotificationListener for UPI apps and Indian banks.
   - TRAI DLT header parsing and Indian bank message corpus.
   - Multi-channel deduplication.
   - First-class manual transaction entry and editing for all platforms (Android & iOS).
5. **Reconciliation:**
   - Internal transfer detection (preventing self-transfers from inflating expenses).
   - Credit card bill payment reconciliation (preventing double counting).
   - Investment allocation routing.
6. **Mandate Tracking:**
   - UPI Autopay & recurring commitment schedule.
   - Liquidity reservation before debit dates.
7. **Premium Slice-Inspired UI:**
   - Safe-to-Spend hero counter with haptic and tactile interactions.
   - Bucket swiper cards.
   - Transaction triage cards (Swipe right to confirm, swipe left to review/quarantine).
   - Full dark theme adhering to approved tokens.
8. **Offline Encrypted Backup:**
   - Passphrase-encrypted JSON/SQLite export and restore.

### Deferred Post-MVP:
- On-device SLM statement parsing.
- Monte Carlo runway simulation.
- PDF statement unlocker / parser.
- Account Aggregator / FinanceKit native bridges.

---

## 6. Key Decisions Requiring Owner Approval

1. **Adopting the Two-Tier Ledger Model (GAP-01 & GAP-02):**
   - *Decision:* Separate physical accounts from virtual allocation buckets in the Drift schema, and use an immutable event ledger to prevent phantom money and preserve audit trails.
   - *Alternative:* Use flat single-table accounts (risks balance corruption and inability to model multiple cards/accounts).
   - *Recommendation:* **Approve Two-Tier Ledger.**

2. **Android Ingestion Scope (GAP-05):**
   - *Decision:* Target Android notification listener exclusively; **zero `READ_SMS` permission**.
   - *Alternative:* Request `READ_SMS` (would violate Google Play policy and break privacy promise).
   - *Recommendation:* **Approve NotificationListener-only approach.**

3. **iOS Strategy (GAP-06):**
   - *Decision:* Make Manual Entry and Share Sheet the primary reliable iOS workflow, with optional Shortcuts deep-link integration.
   - *Alternative:* Promise passive background ingestion on iOS (technically impossible under current iOS security sandbox).
   - *Recommendation:* **Approve honest platform parity model.**

4. **Offline Passphrase Backup (GAP-07):**
   - *Decision:* Implement user-controlled encrypted file backup (AES-GCM / Argon2id) to protect against device loss without introducing cloud servers.
   - *Recommendation:* **Approve Offline Backup.**

---

*Report submitted for owner review and architectural alignment.*
