# Changelog

All notable changes to this project will be documented in this file.

The format loosely follows Keep a Changelog and Semantic Versioning.

## [Unreleased]

### Added

- Full repository scaffolding for public GitHub release:
  - README, LICENSE, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, CHANGELOG
  - Issue templates, PR template, and CI workflow
- Runtime Turkish/English localization support
- Language selector in main UI
- Localization infrastructure for static and dynamic UI text
- Language-independent strategy/filter logic

### Changed

- Media type handling now uses internal invariant keys (`image`, `video`, `audio`, `other`) and localized labels for display
- Scan, filter, swipe, and delete flows now render status/messages using localization keys

### Fixed

- Prevented strategy/filter behavior from depending on translated display text
