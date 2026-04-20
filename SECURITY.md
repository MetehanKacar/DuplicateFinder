# Security Policy

## Supported versions

This is currently a single-script project.
Security fixes are applied to the `main` branch.

## Reporting a vulnerability

Please do not open public issues for security problems.

Instead, report privately with:

- A clear description of the issue
- Steps to reproduce
- Potential impact
- Suggested mitigation (if available)

If private reporting channel is not yet configured, open an issue with minimal
information and request a private contact method.

## Response targets

Best-effort targets:

- Initial response: within 7 days
- Triage decision: within 14 days
- Fix timeline: depends on severity and complexity

## Scope notes

This tool is local-first and does not upload files.
Main risk areas are:

- File deletion flows
- Path handling
- Shell/process invocation behavior
