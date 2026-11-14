## Rivero 0.2 — Your Money - In Flow

**Rivero is a private, local-first money app for Android.** It answers one question first: *how much can I safely spend per day until payday?* No bank login, no cloud account, no ads, no SMS permission. Your data lives encrypted on your phone.

### Why you'll like it
- **One honest number.** Safe to spend per day, built from your *real* spending-account balance, autopay due before payday, and card bills. Tap it to see every line of the calculation.
- **A salary plan that actually moves money.** Split your salary into spending, investments, savings, rent, family and anything you add. Apply it and balances follow between your own accounts. Setting up mid-month? Tell Rivero the money already moved and it never touches it twice.
- **Payments captured for you.** Bank and UPI notifications are recorded as they happen: duplicates merged, OTPs and promotions ignored, and anything uncertain waits for one tap in *To review*.
- **Cards, autopay, EMIs.** Card usage at a glance, upcoming and overdue autopay held back, weekly and month-end schedules handled, card bills recognised as transfers (never double-counted).
- **Owed to you.** Split bills, loans, part-payments, written-off debts, all kept out of your spending.
- **Private by design.** AES-256 encrypted database, biometric lock, hide-amounts mode, and encrypted backups to your own Google Drive or a file that only your passphrase opens.

### What's new in this release
**Safe to spend now follows your bank balance.** Home, the Plan tab, the breakdown sheet and the *Log this anyway?* check all show the same "left to spend". Forgot to log a chai? The balance already knows.

**Plan, for real months.** Every category listed in *Moves out of …* with a total; investments default to your investment account; a plan can never push an account below zero; mid-month setup asks whether this month's money already moved; early-arriving salary starts the next cycle; changing pay day keeps your month.

**Smarter capture.** Reads banks that omit "Rs" (e.g. SBI-style *debited by 500.0*); never lands a bank message on a card; one payment from two notifications is one entry; a spend you logged by hand absorbs the bank's message; card bills paid from the bank lower the card too. Messages Rivero can't read, and failed autopays, show up on Home so nothing is lost silently.

**Autopay you can trust.** Overdue autopays stay reserved, then roll on; 31 Jan rolls to 28 Feb; weekly debits reserved for every week left; typed-in payments move the autopay forward.

**Rock-solid ledger.** All money writes are atomic; double-taps can't apply a payment twice; deleting an imported row can't change a balance.

**Safer and lighter.** The on-phone capture queue is now encrypted and cleared by *Delete all data*; backups include bill photos and account pictures but never raw bank messages; restore checks the backup's version; database lookups are indexed.

### Install
1. Download **`rivero-v….apk`** below and open it (allow *install unknown apps* for your browser once).
2. Answer the three setup questions and enter today's balances.
3. Optional: *Settings → Capture → Notification access*, then *Send a test notification*.

> The **.aab** is for Google Play uploads.
>
> **iPhone (experimental):** `…-ios-unsigned.ipa` is built and started in the iOS simulator by CI but **not tested on a real iPhone**. It is unsigned: sign it with a free Apple ID (AltStore or Sideloadly, renew every 7 days) or a paid developer account. iOS cannot read notifications, so there is no automatic payment capture; log payments, scan bills or import a statement.

📖 **Docs:** user guide, how the money model works, technical implementation and privacy details are on the project site.

Free and open source. Found a bug or a bank message Rivero can't read (with personal details removed)? [Open an issue](https://github.com/scap3sh4rk/Rivero/issues) — that is the most useful way to help.
