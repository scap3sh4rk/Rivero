# Rivero

A private, local-first money app for Android and iOS. Rivero answers one
question first: **how much can I safely spend today?**

Your data lives encrypted on your phone. There is no account, no server and no
bank login. Optional backups go to your own Google Drive, encrypted with a
passphrase only you know.

## How it thinks about money

1. **Salary lands in your salary account.** Everything starts there.
2. **A monthly plan** splits it: what moves to your spending account, what is set
   aside for investments, savings, rent, family and anything else you add.
3. **Only the spending budget counts toward Safe to spend.** That budget is what the
   spending account receives this cycle plus unspent money carried over.
4. **Safe to spend per day** is the budget left, minus autopay due before payday and
   unpaid card bills, divided by the days to payday. Tap the number on Home to see
   every line of the calculation.
5. **Self-transfers are not spending.** Moving money between your own accounts, paying a
   card bill, or being repaid by a friend never inflates your spending or income.

The plan only changes numbers between accounts you track in Rivero. Categories with no
account (rent, family) stay a plan until their real payment is recorded, either by the
bank's message, or by tapping the category when you have paid.

## Features

- Safe to spend per day, with a full breakdown
- Salary plan with carry-over, custom categories and per-category destination accounts
- Accounts and credit cards, with card usage percentage
- Quick log keypad with a built-in calculator, notes and your own categories
- Activity with search, filters, notes, bill photos, and spending analytics
- Money owed to you: split bills, loans, partial repayments
- Autopay and mandate tracking, including pre-debit reminders
- Bank and UPI notification capture on Android (notification access, no SMS permission)
- Bill scanning (on-device text recognition) and CSV statement import (experimental)
- Biometric app lock, privacy mode, light and dark themes, bundled fonts
- Encrypted backup to Google Drive or a file

## Privacy

- The database is encrypted (AES-256, SQLite3 Multiple Ciphers); its key lives in the
  platform keystore.
- Android capture uses *notification access*, never `READ_SMS`. Only notifications from
  known banking, UPI and messaging apps that mention money are kept.
- Nothing is uploaded. Backups are encrypted on the phone before they leave it.
- Android system backup is disabled so the database is never copied without its key.

## Building

Requires the Flutter SDK matching `.github/workflows` (currently 3.50.0).

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generated Drift code
./tool/verify.sh                                           # format, analyze, test
flutter run
```

Generated `*.g.dart` files are not committed.

### Google Drive backup

Backup needs a Google Cloud project with the Drive API enabled and OAuth clients:
a **Web** client (its ID is set in `lib/core/backup/drive_backup.dart`) and an
**Android** client for each signing key (package `dev.scap3sh4rk.rivero`, with the
key's SHA-1). iOS needs its own iOS client.

## Releases

- `develop` is where work happens. `main` is the release branch.
- CI (`.github/workflows/ci.yml`) runs `tool/verify.sh` on every push and pull request.
- Every push to `main` runs `.github/workflows/release.yml`, which builds a signed APK
  and App Bundle and publishes a GitHub Release.
- Signing uses repository secrets: `ANDROID_KEYSTORE_BASE64`,
  `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Without them
  the build falls back to the debug key and is not suitable for distribution.

## Status

Android is the primary target. The iOS project is configured but has not been built or
tested on a device; iOS cannot capture notifications passively, so it relies on manual
entry and statement or bill import.

## Author

Parthiv Kumar Nikku
