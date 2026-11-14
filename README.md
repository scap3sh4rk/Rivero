<div align="center">

<img src="assets/icon/logo.png" width="96" alt="Rivero logo">

# Rivero

### Your Money - In Flow

A private, local-first money app for Android. Know what you can safely spend today: one honest number, **per day until payday**.<br>
No bank login · No cloud account · No ads · No SMS permission.

[![CI](https://github.com/scap3sh4rk/Rivero/actions/workflows/ci.yml/badge.svg)](https://github.com/scap3sh4rk/Rivero/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/scap3sh4rk/Rivero?include_prereleases&label=release&color=4EA3F8)](https://github.com/scap3sh4rk/Rivero/releases/latest)
![Flutter](https://img.shields.io/badge/Flutter-3.50-4EA3F8)
![Platform](https://img.shields.io/badge/Android-primary-2DBE6C)
![iOS](https://img.shields.io/badge/iOS-experimental-F2A93B)

[**Download**](https://github.com/scap3sh4rk/Rivero/releases/latest) ·
[**User guide**](https://scap3sh4rk.github.io/Rivero/user-guide.html) ·
[**How it works**](https://scap3sh4rk.github.io/Rivero/how-it-works.html) ·
[**Technical docs**](https://scap3sh4rk.github.io/Rivero/technical.html)

</div>

---

## Why Rivero

Most money apps tell you where your money went. Rivero tells you **what is left**.

Your salary lands, rent and SIPs go out, cards and autopays are waiting. Rivero does the arithmetic you do in your head every day, and keeps it honest against your *real* bank balance. Tap the number and see every line of the calculation. No black box.

```
left to spend   = spending account balance − plan money still to be paid from it
safe to payday  = left to spend − autopay due − card bills (+ money owed, if counted)
per day         = safe to payday ÷ days to payday
```

## Highlights

| | |
|---|---|
| **One number, fully explained** | Safe to spend per day, with freshness (Verified, Estimated, Stale) and a line-by-line breakdown. |
| **A salary plan that moves money** | Split salary into spending, investments, savings, rent, family and your own categories. Apply it and balances follow between your own accounts, never below zero. Set up mid-month? Say the money already moved and it is never touched twice. |
| **Payments captured for you** | Reads bank and UPI notifications (notification access, never SMS permission). Pick your main UPI app (from those installed), merge duplicates, ignore OTPs and promotions, see what happened to every notification, Accept or Ignore each payment before it counts, and add a payment straight from its phone notification in two taps. |
| **Cards with their own billing cycle** | Days left in each card's cycle, its due date, and whether your accounts can pay the bill. Autopay (including overdue and weekly) held back; card bills recognised as transfers. |
| **Owed, both ways** | Two frames: Owed to you and You owe people (with every bill to pay: cards, loans, autopay). Split bills, loans, borrowing, part-payments, all kept out of your spending. |
| **Activity that answers questions** | Search notes, filter by #tag, type, a day, a month or any from–to range; each day has its own heading and total. |
| **No setup wizard** | Opens straight to Home with a guided tour of every tab; add accounts and your plan in your own order. |
| **Private by design** | AES-256 encrypted database, biometric lock, hide-amounts mode, encrypted backups to your own Google Drive or a file. |
| **Scan and import** | On-device bill scanning (ML Kit); bank, Google Pay and PhonePe statements imported from PDF (Android, password asked and never kept) or CSV. |
| **Rules, reminders, goals** | Rules sort captured payments; repeat payments are suggested as autopay; phone reminders for card bills, autopay and debts; savings goals with progress and "behind by". |
| **Your data, your way** | Export everything to Excel or CSV; automatic daily or weekly encrypted Drive backups; #tags and note search; accounts in other currencies at your own rates. |
| **Yours to style** | "Ink & Sky" dark and paper-light themes, six bundled fonts, your own categories and account types. |

## How it thinks about money

1. **Salary lands in your salary account.** Everything starts there.
2. **A monthly plan splits it:** what moves to your spending account, what is set aside for investments, savings, rent, family and anything you add.
3. **The bank is the truth.** Safe to spend follows what your spending account really holds. The plan is the intention; a bank's "available balance" message always wins over arithmetic.
4. **Self-transfers are not spending.** Moving money between your own accounts, paying a card bill, or being repaid by a friend never inflates your spending or income.

The plan only changes numbers between accounts you track. Categories with no account (rent, family) stay a plan until their real payment is recorded: the bank's message matches the amount, or you tap the category when you have paid.

## Privacy

- The database is encrypted (AES-256, SQLite3 Multiple Ciphers); its key lives in the platform keystore. There is no plaintext fallback.
- Android capture uses *notification access*, never `READ_SMS`. Only notifications that mention money are kept, in a Keystore-encrypted queue, and raw text is deleted after 90 days.
- Nothing is uploaded. Backups are encrypted on the phone with your passphrase before they leave it, and exclude raw bank messages.
- Android system backup is disabled so the database is never copied without its key.

Details: [Privacy & security](https://scap3sh4rk.github.io/Rivero/privacy-security.html).

## Install

Grab the signed APK from the [latest release](https://github.com/scap3sh4rk/Rivero/releases/latest) and open it (allow *install unknown apps* once). A short tour walks you through the app. Add your accounts, set your salary plan, and optionally turn on capture and pick your main UPI app under *Settings → Capture*.

## Build from source

Requires the Flutter SDK matching `.github/workflows` (currently 3.50.0).

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generated Drift code
./tool/verify.sh                                           # format, analyze, test
flutter run
```

Generated `*.g.dart` files are not committed. `tool/verify.sh` is the quality gate (format check, `flutter analyze`, 280+ tests) and must pass before every commit.

### Google Drive backup

Backup needs a Google Cloud project with the Drive API enabled and OAuth clients: a **Web** client (its ID is set in `lib/core/backup/drive_backup.dart`) and an **Android** client for each signing key (package `dev.scap3sh4rk.rivero`, with the key's SHA-1). iOS needs its own iOS client.

## Documentation

The project site (`docs/`, published with GitHub Pages) has:

- **[User guide](https://scap3sh4rk.github.io/Rivero/user-guide.html)**: setup, every screen, capture, backup, FAQ
- **[How it works](https://scap3sh4rk.github.io/Rivero/how-it-works.html)**: the money model, formulas and a worked example
- **[Technical implementation](https://scap3sh4rk.github.io/Rivero/technical.html)**: architecture, data model, ledger, ingestion pipeline, plan engine
- **[Privacy & security](https://scap3sh4rk.github.io/Rivero/privacy-security.html)**: permissions, encryption, threat model
- **[Build & contribute](https://scap3sh4rk.github.io/Rivero/contribute.html)**: build, branches, releases, roadmap

## Releases and branches

- `develop` is where work happens. `main` is the release branch.
- CI (`.github/workflows/ci.yml`) runs `tool/verify.sh` on every push and pull request.
- Every push to `main` runs `.github/workflows/release.yml`, which builds a signed APK and App Bundle, publishes a GitHub Release (notes in `.github/release-notes.md`), and attaches an unsigned iOS `.ipa`.
- `.github/workflows/ios.yml` builds the iOS app on macOS and runs it in the simulator when `ios/` changes (or on demand).
- Signing uses repository secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Without them the build falls back to the debug key and is not suitable for distribution.
- The docs site is published by `.github/workflows/pages.yml` when `docs/` changes on `main`.

## Status

Android is the primary target. **iOS is experimental:** CI builds the iOS app on a macOS runner, starts it in the iOS simulator, and attaches an **unsigned** `.ipa` to each release (sign it with a free Apple ID via AltStore or Sideloadly, or with a paid developer account). It has not been tested on a real iPhone. iOS cannot capture notifications passively, so it relies on manual entry, bill scanning and statement import. See [Install on iPhone](https://scap3sh4rk.github.io/Rivero/user-guide.html#install-on-iphone-experimental).

## Contributing

Issues and pull requests are welcome; pick a template (bug, feature, bank message not recognised, question). Security problems: please report privately, see [SECURITY.md](SECURITY.md). The most useful help right now: real-world bank message formats (personal details removed) for the parser tests, iOS testing, and accessibility feedback. See [Build & contribute](https://scap3sh4rk.github.io/Rivero/contribute.html).

## Author

Parthiv Kumar Nikku
