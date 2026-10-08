# Contributing

Thanks for helping. Bug reports, new exclusion rules and new secret patterns are the most useful contributions.

## Setup

```sh
git clone https://github.com/carmelogallo/ziproj.git
cd ziproj
make test     # run the test suite
make lint     # shellcheck, man page, completions, generated docs
```

`make lint` needs [shellcheck](https://www.shellcheck.net) (`brew install shellcheck`). `mandoc`, `fish` and `zsh` are used when available. The tests use gitleaks and jq when installed and skip the tests that need them otherwise; please run them with gitleaks installed before opening a pull request.

On macOS, `make test` runs `ziproj` with `/bin/bash`, the bash 3.2 that ships with the system.

## Rules for `bin/ziproj`

- **bash 3.2 compatible.** No associative arrays, `mapfile`/`readarray`, `${var,,}`, `[[ -v ]]`, negative array indexes, `&>>` or `|&`.
- **BSD and GNU tools.** Only options that exist in both: `grep -E` (no `-P`), no `sed -i`, no GNU-only `find` or `stat` options.
- **No new dependencies.** gitleaks and jq stay optional.
- **Never print a secret value**, not even in debug output.
- **Never modify the user's files.** Work on copies in the temporary folder.
- `shellcheck` must pass. Disable a check only on the line that needs it, with a comment saying why.

## Adding an exclusion rule

1. Add the pattern to the right list near the top of `bin/ziproj`: `SECRET_FILES`, `SECRET_DIRS`, `JUNK_FILES` or `JUNK_DIRS`.
2. Run `make docs` to regenerate [docs/exclusions.md](docs/exclusions.md).
3. Add the file to the relevant test in `tests/run.sh`.

A folder rule excludes everything inside folders with that name anywhere in the project. Make sure the name cannot be a source folder in common project layouts.

## Adding a secret pattern

1. Add a POSIX extended regular expression to `SECRET_PATTERNS`, with a comment naming the provider.
2. Keep it specific: a fixed prefix plus a length is ideal. Patterns that fire on ordinary code train people to use `-f`.
3. Add a test that **generates** the fake value at run time, like `fake_aws_key` in `tests/run.sh`. Never commit a string that looks like a real credential: it trips secret scanners, including GitHub's push protection.

## Pull requests

- One topic per pull request.
- Update the README, the man page (`man/ziproj.1`) and `CHANGELOG.md` when behaviour changes.
- CI runs the tests on Ubuntu and macOS, with and without gitleaks. All jobs must pass.
