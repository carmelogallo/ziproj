# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-08

First public release.

### Added

- File list from `git ls-files`, so `.gitignore` is honoured, including untracked files and submodules. Folders holding several repositories are handled one repository at a time.
- Default exclusions for secrets and dead weight, applied at any depth and to tracked files too; secret names in any letter case.
- Secret scan on the zip's contents with built-in patterns and, when installed, gitleaks. The project's own gitleaks settings cannot switch the scan off; `ZIPROJ_GITLEAKS_CONFIG` selects a configuration explicitly.
- Blocking by default; `-r` redacts secrets inside the zip and verifies the result.
- `.ziprojignore` per project and per repository, and a global `~/.config/ziproj/ignore`, with `noscan:` rules for known false positives.
- `-a` AI mode, `-n` dry run, `-x` exclusions, `-o` output folder, `-f` force.
- Confirmation prompt when gitleaks is missing; `--no-gitleaks` to skip it.
- Symlinks stored as links, never followed; stale zips removed; largest files reported; zip revealed in Finder or the file manager.
- Completions for fish, zsh and bash; man page; test suite; CI on Ubuntu and macOS.

[1.0.0]: https://github.com/carmelogallo/ziproj/releases/tag/v1.0.0
