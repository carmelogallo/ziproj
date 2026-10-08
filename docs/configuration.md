# Configuration

`ziproj` needs no configuration. Everything below is optional.

## Ignore files

Rules are read from these files, in this order:

| File | Applies to |
|---|---|
| `~/.config/ziproj/ignore` (or `$XDG_CONFIG_HOME/ziproj/ignore`) | every project you zip |
| `.ziprojignore` at the root of the folder you zip | that folder |
| `.ziprojignore` at the root of a repository nested in that folder | that repository |

The `.ziprojignore` file itself is included in the zip, so colleagues can see what was left out.

### Syntax

One rule per line. Blank lines and lines starting with `#` are ignored. Windows line endings are fine.

| Rule | Effect |
|---|---|
| `name` | Exclude every file or folder matching `name`, at any depth. |
| `path/to/thing` | Exclude that path, at any depth (for example both `fastlane/metadata` and `ios/fastlane/metadata`). |
| `/name` | Exclude `name` only at the root of the folder that holds the ignore file. |
| `*.ext` | Globs work. `*` matches any characters, **including `/`**; `?` matches one character and `[abc]` one of a set. |
| `noscan: path` | Keep `path` (a file or a folder) in the zip, but skip the secret scan on it. Relative to the folder that holds the ignore file. |

A trailing `/` is accepted and ignored: `generated/` and `generated` mean the same thing.

### Example

```gitignore
# Store screenshots and metadata: useless to an AI, heavy in a zip
fastlane/metadata

# Generated code, wherever it is
generated

# Only the top-level docs folder, not src/docs
/docs

# A personal convention: a service account file kept under this name
firebase-admin.json

# Test fixtures with fake tokens that look real
noscan: Tests/Fixtures
```

### When to use `noscan:`

Use it for files whose findings you have checked and know to be harmless, typically test fixtures with fake credentials. A `noscan:` file is still zipped, as is. Do not use it to get a real secret past the scan: exclude the file, or use `-r`.

## Command-line exclusions

`-x PATTERN` (or `--exclude=PATTERN`) follows the same syntax as an ignore file rule and can be repeated:

```sh
ziproj -x fastlane/metadata -x '*.mp4' -x /docs
```

Quote patterns that contain `*` so your shell does not expand them.

## Environment variables

| Variable | Effect |
|---|---|
| `ZIPROJ_OUT` | Default output folder, instead of `~/Downloads`. `-o` takes precedence. |
| `ZIPROJ_NO_OPEN` | Set to `1` to never reveal the zip in Finder or the file manager. |
| `ZIPROJ_GITLEAKS` | Name or path of the gitleaks executable (default: `gitleaks`). |
| `ZIPROJ_GITLEAKS_CONFIG` | A gitleaks configuration file to scan with, for example one that adds rules for your company's tokens. Without it gitleaks uses its default rules; a `.gitleaks.toml` inside the project is never used. |
| `ZIPROJ_JQ` | Name or path of the jq executable (default: `jq`). |
| `NO_COLOR` | Set to anything to disable colours ([no-color.org](https://no-color.org)). |
| `XDG_CONFIG_HOME` | Where the global ignore file lives (default: `~/.config`). |

## Exit status

| Code | Meaning |
|---|---|
| `0` | The zip was written, or a dry run found no secrets. |
| `1` | Secrets were found and nothing was written, the redaction could not be verified, or an error occurred. |
| `2` | Invalid options. |
| `130` | Interrupted with Ctrl-C. |
| `143` | Terminated (SIGTERM). |

With `-f`, the zip is written and the exit status is `0` even when secrets were found; they are still listed.

## Output

The status line (`zipping 841/1934 (43%)`) is drawn on standard error and only when it is a terminal. The summary goes to standard output, warnings and findings to standard error, so both can be redirected separately:

```sh
ziproj -n > files.txt      # file list and summary, without progress or warnings
```
