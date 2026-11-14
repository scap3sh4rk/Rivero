## What and why

<!-- One or two sentences. Link the issue: Fixes #123 -->

## Checklist

- [ ] `./tool/verify.sh` passes (format, analyze, tests)
- [ ] Behaviour change has a test (money paths need a regression test)
- [ ] Money stays whole paise (`int`), no floating point
- [ ] No `READ_SMS`, no plaintext database, no data leaves the phone
- [ ] Docs updated if behaviour users see changed (`docs/`)
- [ ] No personal data in code, tests or screenshots

## Notes for the reviewer
