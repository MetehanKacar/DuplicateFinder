# Contributing

Thanks for your interest in improving DuplicateFinder.

## Before you start

- Read `README.md` for product behavior.
- Check open issues before creating a new one.
- For substantial changes, open an issue first to discuss approach.

## Development setup

Run from Windows PowerShell in STA mode:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\DuplicateFinder.ps1
```

## Contribution principles

- Keep behavior predictable and safe.
- Preserve duplicate-detection correctness.
- Prefer small, focused pull requests.
- Avoid unrelated refactors in the same PR.

## Coding guidelines

- Keep PowerShell code readable and explicit.
- Use clear function names.
- Avoid destructive default behavior.
- Keep delete actions reversible where possible.

## Localization guidelines

This project supports Turkish and English.

When adding user-visible text:

1. Add keys to `T` function for both `tr` and `en`.
2. Use `T 'key'` in UI logic, not hardcoded strings.
3. Keep strategy/filter logic language-independent (index/key based).

See `docs/LOCALIZATION.md` for details.

## Pull request checklist

- [ ] Code runs without parse errors.
- [ ] Existing behavior is not broken.
- [ ] New/changed UI text is localized (TR + EN).
- [ ] README/docs updated if behavior changed.
- [ ] PR title and description clearly explain the change.

## Commit message tips

Recommended style:

- `feat: add language switch in top panel`
- `fix: avoid filter mismatch after language change`
- `docs: add architecture overview`

## Reporting bugs

Use the bug template and include:

- Repro steps
- Expected behavior
- Actual behavior
- Windows + PowerShell version
- Sample path structure (if relevant)
