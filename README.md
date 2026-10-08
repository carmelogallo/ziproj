# ziproj

**Zip a project to share with an AI assistant or a colleague, without your secrets, build output or caches.**

[![CI](https://github.com/carmelogallo/ziproj/actions/workflows/ci.yml/badge.svg)](https://github.com/carmelogallo/ziproj/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platforms: macOS | Linux](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux-lightgrey.svg)

Dropping a zip of your project into ChatGPT, Claude or Gemini, or sending it to a colleague, takes seconds. It is also one of the fastest ways to leak credentials. A plain `zip -r` takes everything: `.env` files, signing keys, API keys hard-coded in a config, plus hundreds of megabytes of `node_modules`, `DerivedData` and build output.

`ziproj` takes only what the project needs, checks what it is about to share, and stops if it finds a secret.

```console
$ ziproj
  MyApp [git, gitleaks] 214 files — BLOCKED, no zip written
  ⚠ possible secrets (2):
    Configurations/Debug.xcconfig:2 (generic-api-key)
    Configurations/Release.xcconfig:2 (generic-api-key)
  re-run with -r to redact them inside the zip

$ ziproj -r
  MyApp [git, gitleaks] 214 files — 1.8M in 2s → ~/Downloads/MyApp.zip
  secrets redacted in the zip (2):
    Configurations/Debug.xcconfig:2 (generic-api-key)
    Configurations/Release.xcconfig:2 (generic-api-key)
```

Inside the zip, `Configurations/Release.xcconfig` now reads `API_KEY = REDACTED`. The file on your disk is untouched.

> [!IMPORTANT]
> The safest project to share is one with no secrets in it. `ziproj` is a safety net, not a guarantee: read [Limitations](#limitations).

## Contents

- [What it does](#what-it-does)
- [Install](#install)
- [Usage](#usage)
- [Ignore files](#ignore-files)
- [Secret scanning and redaction](#secret-scanning-and-redaction)
- [Limitations](#limitations)
- [FAQ](#faq)
- [Documentation](#documentation)
- [Contributing](#contributing) · [Security](#security) · [License](#license)

## What it does

- **Honours `.gitignore`.** Inside a git repository the file list comes from `git ls-files`: tracked files, plus untracked files that are not ignored, plus submodules. Run it on a folder that holds several repositories and each one is listed with its own `.gitignore`.
- **Leaves out secrets at any depth and in any letter case**, even when they are committed: `.env*`, `.envrc`, `.npmrc`, `*.pem`, `*.p8`, `*.p12`, `*.keystore`, provisioning profiles, `GoogleService-Info.plist`, `google-services.json`, service account files, `Secrets.*`, `local.properties`, Terraform state, local databases, `.ssh/`, `.aws/` and more.
- **Leaves out dead weight** for iOS, Android, web, backend, Python, Rust and Java projects: `node_modules`, `Pods`, `DerivedData`, `.build`, `build`, `dist`, `.next`, `target`, `.venv`, caches, logs, `.DS_Store`, app packages and archives.
- **Scans exactly what ends up in the zip** with built-in patterns and, when installed, [gitleaks](https://github.com/gitleaks/gitleaks).
- **Blocks or redacts.** By default nothing is written when a secret is found. With `-r` the secrets are replaced with `REDACTED` inside the zip, and the result is scanned again.
- **Never prints a secret.** Findings show `path:line` only.
- **Never follows symlinks**, so a link pointing outside the project cannot pull in `~/.ssh`.
- **Never modifies your files**, and never leaves a stale zip behind: a blocked run also removes the previous one.
- **Shows the largest files**, so dead weight is easy to spot, and reveals the zip in Finder (or your Linux file manager), ready to drag into a chat.

## Install

### Requirements

| | |
|---|---|
| **bash 3.2+**, `zip`, `unzip`, `find`, `grep`, `awk` | Preinstalled on macOS. On Debian/Ubuntu: `sudo apt install zip unzip`. |
| **git** | Recommended, to honour `.gitignore`. |
| **[gitleaks](https://github.com/gitleaks/gitleaks)** | Strongly recommended: `brew install gitleaks`. Without it ziproj asks before going on. |
| **jq** | Needed by `-r` when gitleaks is installed: `brew install jq` or `sudo apt install jq`. |

`ziproj` is a standalone executable, so it works the same from **fish, zsh and bash**. Completions for all three are included. On Windows, use it from WSL.

### With make (recommended)

```sh
git clone https://github.com/carmelogallo/ziproj.git
cd ziproj
make install                       # ~/.local/bin, man page, completions
# or: sudo make install PREFIX=/usr/local
```

`make install` tells you if `~/.local/bin` is missing from your `PATH`, and how to add it for your shell. For zsh completions, make sure `~/.local/share/zsh/site-functions` is in your `fpath` before `compinit`.

To update, `git pull && make install`. To remove, `make uninstall`.

### Single file

`ziproj` is one readable bash script. Download it, read it, and put it on your `PATH`:

```sh
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/carmelogallo/ziproj/main/bin/ziproj -o ~/.local/bin/ziproj
chmod +x ~/.local/bin/ziproj
```

## Usage

```sh
ziproj                      # zip the current folder into ~/Downloads/<name>.zip
ziproj ~/Code/my-app        # zip another folder
ziproj -n                   # dry run: list and scan, write nothing
ziproj -r                   # redact secrets inside the zip instead of blocking
ziproj -a                   # AI mode: also drop images, PDFs, fonts, audio, video
ziproj -x docs -x '*.mp4'   # exclude more (files, folders or globs)
ziproj -o ~/Desktop         # write somewhere else
```

Short options can be combined: `ziproj -nar` is a dry run in AI mode with redaction. For an AI assistant, `ziproj -ar` is usually what you want.

| Option | |
|---|---|
| `-n`, `--dry-run` | List what would be zipped and scan it. Writes nothing. |
| `-r`, `--redact` | Replace detected secrets with `REDACTED` inside the zip instead of blocking. |
| `-a`, `--ai` | Also leave out images, PDFs, fonts, audio, video and design files. |
| `-x`, `--exclude PAT` | Exclude a file, folder or glob at any depth. A leading `/` anchors it to the root. Repeatable. |
| `-o`, `--out DIR` | Output folder. Default: `$ZIPROJ_OUT`, or `~/Downloads`. |
| `-f`, `--force` | Write the zip even with secrets in plain text. Prefer `-r`. |
| `--no-gitleaks` | Do not use gitleaks, and do not ask about it. |
| `--no-open` | Do not reveal the zip in Finder or the file manager. |
| `-h`, `--help` / `-V`, `--version` | Help and version. |

Exit status: `0` zip written (or clean dry run), `1` blocked or error, `2` invalid options. Run `man ziproj` for the full reference.

## Ignore files

Add your own rules, one per line, in either place:

- **`.ziprojignore`** in the project. In a folder with several repositories, each repository can have its own.
- **`~/.config/ziproj/ignore`** for rules that apply to every project.

```gitignore
# Exclude at any depth
fastlane/metadata
generated/

# Exclude only at the root
/docs

# Keep in the zip, but skip the secret scan (known false positives)
noscan: Tests/Fixtures
```

`*` matches any characters, including `/`. Details in [docs/configuration.md](docs/configuration.md).

## Secret scanning and redaction

The scan runs on a copy of exactly what is inside the zip, after every exclusion.

- **Built-in patterns** catch private keys and well-known token formats: AWS, Google, OpenAI, Anthropic, GitHub, GitLab, Slack, Stripe, SendGrid, npm, Hugging Face, Azure, JWTs and database URLs with a password.
- **gitleaks** adds hundreds of rules and entropy checks, including generic API keys like `API_KEY = …` in an `.xcconfig` or a `build.gradle.kts`. If gitleaks is not installed, ziproj explains the risk and asks whether to go on. In a non-interactive shell it stops, unless you pass `--no-gitleaks`.
- **The project cannot switch the scan off.** A `.gitleaks.toml`, a `.gitleaksignore` or a `gitleaks:allow` comment inside the project is ignored for the scan; use `noscan:` for false positives you have checked.

With `-r`, every detected value is replaced with `REDACTED` in the zip's copy of the file. The same value is also replaced in any other file that contains it, even one no scanner flagged, and private key blocks become `REDACTED-PRIVATE-KEY`. Then the redacted files are scanned again: if anything is still detected, the zip is not written.

More in [docs/how-it-works.md](docs/how-it-works.md).

## Limitations

- **A scanner only finds what it recognises.** A password or token in an unusual format can pass both the built-in patterns and gitleaks, and then it is zipped in plain text, with or without `-r`. Check the list with `-n` before sharing anything sensitive.
- **The denylist is generic.** If your project keeps secrets in a file with an unusual name, add it to `.ziprojignore`.
- **Redaction works on text.** Secrets inside binary files are not detected or redacted.
- **Never use `-f` to get past a finding you have not read.**

## FAQ

**Why not `git archive`?**
It respects `.gitignore` but includes every committed file, secrets included, leaves out your uncommitted work, and scans nothing.

**Doesn't `.gitignore` already handle this?**
Only for files you never committed, and only inside one repository. Plenty of real repositories have a committed `.env`, a `GoogleService-Info.plist` or an API key in a config file. `ziproj` excludes those even when tracked, and scans the rest.

**Does anything leave my machine?**
No. Everything runs locally: listing, zipping and scanning. gitleaks runs locally too.

**Why a bash script and not a fish or zsh function?**
One implementation behaves identically in every shell, and a security tool should not have three copies of its logic drifting apart. Completions make it feel native in fish, zsh and bash.

**Should I share my project with an AI at all?**
Prefer tools that read your code in place, with permissions you control. When you do need to hand over a zip, make it a clean one.

## Documentation

- [How it works](docs/how-it-works.md): the pipeline, design decisions and threat model
- [Configuration](docs/configuration.md): ignore files, environment variables, exit codes
- [Default exclusions](docs/exclusions.md): the complete list
- `man ziproj`, after `make install`

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). New exclusion rules and secret patterns are especially useful.

## Security

If you find a way to make `ziproj` leak something it should have caught, please report it privately, as described in [SECURITY.md](SECURITY.md). Never paste a real secret into an issue.

## License

[MIT](LICENSE) © 2026 Carmelo Gallo
