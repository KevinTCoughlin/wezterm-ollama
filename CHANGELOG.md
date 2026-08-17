# Changelog

All notable changes to this project are documented here. The project follows
[Semantic Versioning](https://semver.org/).

## Unreleased

### Fixed

- Load the plugin without relying on a hard-coded checkout path.
- Parse Ollama responses as JSON and handle HTTP, timeout, and malformed-response failures.
- Resolve partial options consistently for public action helpers.
- Isolate model and status caches by Ollama host.
- Expand `~` in the session directory and validate unsafe configuration values.

### Added

- Lua unit tests, a real-WezTerm integration check, and CI.

## 1.0.0 - 2026-01-16

- Initial stable release.
