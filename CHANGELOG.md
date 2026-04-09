# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-04-09

### Added

- Initial release
- Centered floating progress bar with 60fps smooth animation
- Post-update results via snacks.nvim picker (ivy layout)
- Floating markdown fallback when snacks.nvim is unavailable
- Commit log preview per changed plugin
- Rollback detection (labels commits when a plugin moves backward)
- Auto-update cadence: `manual`, `daily`, `weekly`, `monthly`
- `TinyPackProgress` highlight group (links to `DiagnosticOk` by default)
- Configurable command name via `command` option
- `picker` option to force fallback UI for testing

[0.1.0]: https://github.com/swaits/tiny-packupdate.nvim/releases/tag/v0.1.0
