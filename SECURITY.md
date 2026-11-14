# Security policy

Rivero handles personal financial data, so security and privacy come first. Thank you for helping keep it safe.

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Report it privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability**
(<https://github.com/scap3sh4rk/Rivero/security/advisories/new>).

Include:

- what you found and where (screen, file or flow),
- the steps to reproduce it,
- the impact you think it has (for example, "another app can read the database"),
- the Rivero version (release tag) and Android version.

Do not include real financial data, and do not test against anyone else's data or accounts.

## What to expect

- An acknowledgement within a few days.
- An assessment and, if confirmed, a fix in the next release, with credit to you if you want it.
- A request to keep details private until a fixed version is available.

This is a volunteer project, so timelines are best effort.

## Supported versions

Only the **latest release** receives security fixes. Please update before reporting.

## Scope

In scope:

- The Android app and its build/release workflows.
- Local data storage and encryption (database, capture queue, backups).
- The notification-capture path and anything that could make Rivero read or send data it should not.
- The encrypted backup format and Google Drive backup handling.

Out of scope:

- Problems that need a rooted or already-compromised phone, or physical access to an unlocked phone.
- Vulnerabilities in third-party apps or in Android itself.
- Missing hardening that has no demonstrated impact, and automated-scanner output without a working scenario.
- Social engineering and denial of service.

## Design commitments (what a report can be measured against)

- No `READ_SMS` or other SMS permission, ever.
- The database is encrypted (AES-256) with a key held by the platform keystore; there is no plaintext fallback.
- Nothing is uploaded. The only network use is a Google Drive backup the user starts, encrypted on the phone with the user's passphrase first.
- Android system backup is disabled (`allowBackup="false"`).
- The capture queue is encrypted with a key that never leaves the Android Keystore.
- Raw bank message text is deleted after 90 days and never included in backups.

Details: [Privacy & security](docs/privacy-security.html).

## Protect yourself

- Turn on **App lock** in Settings.
- Make regular encrypted backups and keep the passphrase safe. It cannot be recovered.
- Install Rivero only from this repository's [releases](https://github.com/scap3sh4rk/Rivero/releases).
