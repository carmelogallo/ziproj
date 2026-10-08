# How it works

`ziproj` is a single bash script ([`bin/ziproj`](../bin/ziproj)). Every run goes through the same five steps, and nothing reaches your output folder until all of them have passed.

## 1. List the files

| Where you run it | How files are listed |
|---|---|
| Inside a git repository (or one of its subfolders) | `git ls-files --cached --recurse-submodules` plus `git ls-files --others --exclude-standard`: tracked files, untracked files that are not ignored, and submodule contents. Deleted files are skipped. |
| In a folder that is not a repository | Every repository found inside it is listed through git, as above, with its own `.gitignore`. Everything outside those repositories is listed with `find`, which skips the excluded folders without walking into them. |

Going through git is what makes `.gitignore` count: if your project ignores `Config/Keys.xcconfig`, so does `ziproj`. Repositories nested inside other repositories are treated as submodules and listed by their parent.

`ziproj` refuses to run on `/`, on your home folder, or on any folder that contains your home folder.

## 2. Zip into a private temporary folder

The list is passed to `zip` with the [default exclusions](exclusions.md), your [ignore files](configuration.md#ignore-files) and the `-x` patterns, through a pattern file so that no pattern can be mistaken for a `zip` option. These rules apply even to files tracked by git: a committed `.env` stays out. Secret file names are matched in any letter case, because the default macOS file system treats `.ENV` and `.env` as the same file.

- `zip -y` stores symbolic links as links. A link pointing outside the project is never followed, so it cannot pull in `~/.ssh` or another project.
- `zip -X` leaves out the owner's user and group ids.
- The zip is built in a folder created with `mktemp -d`, which only you can read, and deleted on exit, including on Ctrl-C.

At the start of every run that writes a zip, an existing `<name>.zip` in the output folder is deleted. If this run is blocked or fails, there is no stale zip left to upload by mistake.

## 3. Scan what is in the zip

The scan reads the list of entries back from the zip itself, so it checks exactly what would be shared, after every exclusion.

1. **Built-in patterns** (POSIX extended regular expressions, so they behave the same with BSD and GNU `grep`) catch private keys and well-known token formats. They are a safety net that works without anything installed.
2. **gitleaks**, when installed, scans a copy of the zip's contents. Its rules cover hundreds of providers, and its generic rules use keywords and entropy to find values like `API_KEY = …` that have no recognisable format.

   The project being zipped must not be able to switch this off, so in the scan copy `ziproj` deletes any `.gitleaks.toml` and `.gitleaksignore`, defuses `gitleaks:allow` comments, and ignores the `GITLEAKS_CONFIG` variable. gitleaks therefore runs with its default rules, or with the configuration you choose explicitly through `ZIPROJ_GITLEAKS_CONFIG`. The zip itself keeps those files unchanged.

Symbolic links and files marked `noscan:` are not scanned. Binary files are skipped by both scanners.

Findings are reported as `path:line`, plus the gitleaks rule when gitleaks found it. The secret value itself is never printed.

If gitleaks is not installed, `ziproj` explains what that means and asks before going on. In a non-interactive shell it stops instead, unless `--no-gitleaks` is given. A dry run (`-n`) never asks; its summary says `built-in scan only`. If gitleaks is installed but fails to run, `ziproj` stops rather than silently falling back.

## 4. Block, or redact and verify

**Default:** if anything was found, nothing is written and the exit status is `1`.

**With `-r`:**

1. The values to remove are collected: the text matched by the built-in patterns, and the `Secret` field of each gitleaks finding (read with `jq`). The gitleaks report that holds them stays in the private temporary folder and is deleted on exit.
2. Every file with a finding is rewritten into the temporary folder:
   - each known value becomes `REDACTED`, together with the rest of its token, because some rules capture only the beginning of a long key;
   - each private key block, from `-----BEGIN … PRIVATE KEY-----` to the matching `END` line, becomes `REDACTED-PRIVATE-KEY`, whether it spans several lines or sits on one line of a JSON file.
3. Every other scanned file that contains one of those values is rewritten the same way and listed as `(same value)`. This catches a key repeated in a second config that no rule flagged on its own.
4. The rewritten files replace the originals inside the zip.
5. The rewritten files are scanned again with the built-in patterns and gitleaks. Anything still detected is reported as `redaction incomplete` and blocks the zip.

Values shorter than 6 characters are not used for redaction, to avoid rewriting unrelated text. Your files on disk are never modified.

## 5. Write the zip

Only after the steps above is the zip moved to the output folder. On macOS it is then revealed in Finder; on a Linux desktop the output folder is opened with `xdg-open`. `--no-open` or `ZIPROJ_NO_OPEN=1` turns this off, and nothing is opened when the output is not a terminal.

The summary lists the five largest files above 1 MB, which is usually where dead weight hides.

## Threat model

**What `ziproj` protects against:** the everyday mistake of sharing more than you meant to. Environment files, signing keys and certificates, cloud credentials, API keys committed to a config, local databases, files reachable through symlinks, and a forgotten zip from a previous attempt.

**What it does not protect against:**

- A secret in a format no scanner recognises. Scanning lowers the risk; it cannot prove a project is clean.
- Secrets inside binary files, such as a compiled app or a database in an unusual format.
- Sensitive content that is not a credential: personal data in fixtures, internal hostnames, proprietary code you are not allowed to share.
- Anything that happens after the zip leaves your machine.

Review the file list with `-n` before you share, and keep secrets out of your repositories in the first place: environment variables, a secrets manager, or a gitignored local config.

## Design decisions

- **One executable, every shell.** A standalone script runs identically from fish, zsh and bash. A security tool should not keep three copies of its logic in sync.
- **bash 3.2 compatible.** It is the `/bin/bash` that ships with macOS, so `ziproj` needs nothing extra there. CI runs the test suite with it.
- **Block by default.** A finding stops the zip until you decide. `-r` is one keystroke away; `-f` exists but is never suggested.
- **Exclusions apply to tracked files too.** `.gitignore` describes what a repository should contain, not what is safe to share.
- **Scan the result, not the source.** Scanning the zip's own entry list means every exclusion, ignore file and symlink rule has already been applied.
