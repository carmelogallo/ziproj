# Security policy

`ziproj` exists to keep secrets out of the zips you share, so a way to get a secret past it is treated as a security issue.

## What to report privately

- A file or secret that ends up in the zip although `ziproj` claims to exclude or detect it.
- A way to make `ziproj` read or zip files outside the project folder.
- A way for a crafted project (file names, links, ignore files) to run commands or write outside the output and temporary folders.
- A secret value printed to the terminal.

## How to report

Use GitHub's private reporting: open the **Security** tab of this repository and choose **Report a vulnerability**. Please include the `ziproj --version` output, your OS, `bash --version`, `gitleaks version`, and the smallest project layout that reproduces the problem.

**Never include a real credential.** Use a fake value in the same format. If you exposed a real secret while testing, rotate it.

This is a personal open source project, so reports are handled on a best-effort basis. Fixes are released as soon as they are ready and credited to the reporter, unless you prefer otherwise.

## What to open as a public issue instead

- A file type that should be excluded by default but is not listed in [docs/exclusions.md](docs/exclusions.md).
- A widely used token format that the built-in patterns miss.
- False positives.

These are improvements, not vulnerabilities: `ziproj` documents that it only catches what it recognises. The issue templates explain what to include.

## Supported versions

Only the latest release receives fixes.
