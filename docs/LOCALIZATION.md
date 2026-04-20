# Localization Guide

This project supports two UI languages:

- `tr` (Turkish)
- `en` (English)

## Core principles

- All user-visible text should come from localization keys via `T 'key'`.
- Logic must not depend on translated display strings.
- Use stable internal keys/indexes for strategy/filter behavior.

## Main pieces

- `T([string]$Key, [object[]]$Args = @())`
  - Returns localized string
  - Supports format args (`{0}`, `{1}`, ...)
- `Apply-Language`
  - Rebinds control texts at runtime
  - Rebuilds strategy/media filter combo items
- Language selector (`TR` / `EN`) in top panel

## Add a new text key

1. Add `tr` and `en` entries in `T` function.
2. Replace hardcoded UI string with `T 'new_key'`.
3. If formatted, pass args:

```powershell
$lblStatus.Text = T 'status_fast_scan' @($current, $total)
```

## Add a new language

1. Extend language detection and selector values.
2. Add language branch in `T` function.
3. Provide complete translation set.
4. Test all major flows:
   - Scan
   - Filter
   - Swipe review
   - Delete preview

## Avoid common mistakes

- Do not switch on combo display text.
  - Use `SelectedIndex` or internal key arrays.
- Do not hardcode MessageBox titles/messages.
- Do not forget runtime updates in `Apply-Language`.
