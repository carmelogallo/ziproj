#!/usr/bin/env bash
#
# ziproj test suite. No dependencies beyond what ziproj itself needs.
#
#   tests/run.sh            run every test
#   tests/run.sh redact     run only tests whose name contains "redact"
#
# Environment:
#   ZIPROJ_TEST_SHELL   interpreter for bin/ziproj (default: bash).
#                       On macOS use /bin/bash to cover bash 3.2.
#
# Fake secrets are generated at run time from random bytes, so this
# repository never contains anything that looks like a real credential.

set -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd -P)
ZIPROJ="$HERE/../bin/ziproj"
TEST_SHELL=${ZIPROJ_TEST_SHELL:-bash}
FILTER=${1:-}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/ziproj-tests.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

# Isolate from the real environment: home folder, global ignore, git identity.
export HOME="$WORK/home"
export XDG_CONFIG_HOME="$HOME/.config"
export NO_COLOR=1 ZIPROJ_NO_OPEN=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_NOSYSTEM=1
unset ZIPROJ_OUT ZIPROJ_GITLEAKS ZIPROJ_JQ
mkdir -p "$HOME/Downloads"

HAS_GITLEAKS=0
command -v gitleaks >/dev/null 2>&1 && HAS_GITLEAKS=1
HAS_JQ=0
command -v jq >/dev/null 2>&1 && HAS_JQ=1

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

fail() {
    printf '    %s\n' "$@"
    if [ -s "$WORK/stdout" ] || [ -s "$WORK/stderr" ]; then
        printf '    --- stdout ---\n'
        sed 's/^/    | /' "$WORK/stdout"
        printf '    --- stderr ---\n'
        sed 's/^/    | /' "$WORK/stderr"
    fi
    exit 1
}

skip() {
    printf '%s\n' "$*" >"$WORK/skip-reason"
    exit 3
}

# new_project NAME -> creates an empty folder and cds into it
new_project() {
    PROJECT="$WORK/projects/$1"
    mkdir -p "$PROJECT"
    cd "$PROJECT" || exit 1
    DEST="$WORK/dest/$1"
    mkdir -p "$DEST"
    ZIPFILE="$DEST/$1.zip"
}

git_repo() { # git_repo [DIR] - init and commit everything
    (cd "${1:-.}" && git init -q && git add -A && git commit -qm init) >/dev/null 2>&1
}

# ziproj ARGS... - runs bin/ziproj in $PROJECT, writing to $DEST, without gitleaks
ziproj() {
    (cd "$PROJECT" && "$TEST_SHELL" "$ZIPROJ" -o "$DEST" --no-gitleaks "$@") \
        >"$WORK/stdout" 2>"$WORK/stderr" </dev/null
    RC=$?
}

# ziproj_gitleaks ARGS... - same, with gitleaks if installed
ziproj_gitleaks() {
    (cd "$PROJECT" && "$TEST_SHELL" "$ZIPROJ" -o "$DEST" "$@") \
        >"$WORK/stdout" 2>"$WORK/stderr" </dev/null
    RC=$?
}

ziproj_raw() { # no implicit options
    ("$TEST_SHELL" "$ZIPROJ" "$@") >"$WORK/stdout" 2>"$WORK/stderr" </dev/null
    RC=$?
}

expect_rc() { [ "$RC" = "$1" ] || fail "exit status $RC, expected $1"; }

expect_in_zip() {
    local f
    [ -f "$ZIPFILE" ] || fail "no zip written"
    for f in "$@"; do
        unzip -Z1 "$ZIPFILE" | grep -qxF -- "$f" || fail "missing from the zip: $f"
    done
}

expect_not_in_zip() {
    local f
    [ -f "$ZIPFILE" ] || fail "no zip written"
    for f in "$@"; do
        if unzip -Z1 "$ZIPFILE" | grep -qxF -- "$f"; then fail "should not be in the zip: $f"; fi
    done
}

expect_no_zip() { [ ! -e "$ZIPFILE" ] || fail "a zip was written: $ZIPFILE"; }

# Text checks across stdout + stderr
expect_output() {
    cat "$WORK/stdout" "$WORK/stderr" | grep -qF -- "$1" || fail "output does not contain: $1"
}
expect_no_output() {
    if cat "$WORK/stdout" "$WORK/stderr" | grep -qF -- "$1"; then fail "output must not contain: $1"; fi
}

# The zip's file contents must not contain VALUE anywhere.
expect_zip_without() {
    [ -f "$ZIPFILE" ] || fail "no zip written"
    if unzip -p "$ZIPFILE" | LC_ALL=C grep -qF -- "$1"; then fail "the zip still contains a secret value"; fi
}

expect_zip_file_contains() { # PATH TEXT
    unzip -p "$ZIPFILE" "$1" | grep -qF -- "$2" || fail "$1 in the zip does not contain: $2"
}

# Random fake secrets (never stored in this repository).
rand_alnum() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c "$1"; }
fake_aws_key() { printf 'AK%s%s' 'IA' "$(LC_ALL=C tr -dc 'A-Z2-7' </dev/urandom 2>/dev/null | head -c 16)"; }
fake_stripe_live() { printf 'sk_%s_%s' 'live' "$(rand_alnum 24)"; }
# A random generic API key that gitleaks flags. gitleaks drops candidates that
# contain common words or have low entropy, so retry until it reports one.
gitleaks_key() {
    local dir="$WORK/gitleaks-probe" key n=0
    while [ $n -lt 25 ]; do
        n=$((n + 1))
        key=$(rand_alnum 32)
        rm -rf "$dir" && mkdir -p "$dir/src"
        printf 'API_KEY = %s\n' "$key" >"$dir/src/probe.xcconfig"
        if gitleaks dir --help >/dev/null 2>&1; then
            (cd "$dir" && gitleaks dir src --no-banner --report-format json --report-path report.json) >/dev/null 2>&1
        else
            (cd "$dir" && gitleaks detect --no-git --source src --no-banner --report-format json --report-path report.json) >/dev/null 2>&1
        fi
        if grep -q '"RuleID"' "$dir/report.json" 2>/dev/null; then
            printf '%s' "$key"
            return 0
        fi
    done
    return 1
}

fake_pem() {
    local kind="PRIVATE KEY"
    printf -- '-----BEGIN RSA %s-----\n' "$kind"
    rand_alnum 64; echo
    rand_alnum 64; echo
    rand_alnum 64; echo
    printf -- '-----END RSA %s-----\n' "$kind"
}

# --------------------------------------------------------------------------
# Tests
# --------------------------------------------------------------------------

test_help_version_and_usage_errors() {
    ziproj_raw --help
    expect_rc 0
    expect_output "Usage: ziproj"
    ziproj_raw --version
    expect_rc 0
    expect_output "ziproj "
    ziproj_raw --bogus
    expect_rc 2
    ziproj_raw -x
    expect_rc 2
    ziproj_raw one two
    expect_rc 2
}

test_secret_files_are_excluded_at_any_depth() {
    new_project secrets
    mkdir -p App/Sources backend/config web Keys android/app ios/Runner
    echo 'print(1)' >App/Sources/main.swift
    echo 'X=1' >.env
    echo 'X=1' >backend/.env.production
    echo 'X=1' >web/.env.local
    echo 'X=1' >.envrc
    echo 'x' >.npmrc
    echo 'x' >secrets.properties
    echo 'x' >android/local.properties
    echo 'x' >android/app/google-services.json
    echo 'x' >ios/Runner/GoogleService-Info.plist
    echo 'x' >Keys/AuthKey_ABC123.p8
    echo 'x' >Keys/dist.p12
    echo 'x' >Keys/server.pem
    echo 'x' >Keys/App.mobileprovision
    echo 'x' >Keys/release.keystore
    echo 'x' >terraform.tfstate
    echo 'x' >backend/app.db
    echo 'x' >backend/config/Secrets.swift
    ziproj
    expect_rc 0
    expect_in_zip App/Sources/main.swift
    expect_not_in_zip .env backend/.env.production web/.env.local .envrc .npmrc secrets.properties \
        android/local.properties android/app/google-services.json ios/Runner/GoogleService-Info.plist \
        Keys/AuthKey_ABC123.p8 Keys/dist.p12 Keys/server.pem Keys/App.mobileprovision \
        Keys/release.keystore terraform.tfstate backend/app.db backend/config/Secrets.swift
}

test_secret_files_are_excluded_in_any_letter_case() {
    new_project anycase
    mkdir -p Keys SECRETS
    echo 'x' >main.swift
    echo 'X=1' >.ENV
    echo 'x' >Keys/Server.PEM
    echo 'x' >Keys/Cert.P12
    echo 'x' >Keys/ID_RSA
    echo 'x' >SECRETS/token.txt
    ziproj
    expect_rc 0
    expect_in_zip main.swift
    expect_not_in_zip .ENV Keys/Server.PEM Keys/Cert.P12 Keys/ID_RSA SECRETS/token.txt
}

test_build_output_and_caches_are_excluded() {
    new_project junk
    mkdir -p src node_modules/x .build/debug DerivedData/a build Pods/A .next/cache \
        api/__pycache__ .venv/lib target/debug sub/node_modules/y
    echo 'x' >src/index.ts
    for f in node_modules/x/i.js .build/debug/o DerivedData/a/b build/out Pods/A/a.m \
        .next/cache/c api/__pycache__/m.pyc .venv/lib/l target/debug/t sub/node_modules/y/i.js; do
        echo 'x' >"$f"
    done
    echo 'x' >.DS_Store
    echo 'x' >debug.log
    ziproj
    expect_rc 0
    expect_in_zip src/index.ts
    if unzip -Z1 "$ZIPFILE" | grep -qE '^(node_modules|\.build|DerivedData|build|Pods|\.next|\.venv|target|sub/node_modules)/|__pycache__|\.DS_Store|debug\.log'; then
        fail "junk found in the zip"
    fi
}

test_build_named_file_is_kept() {
    new_project buildfile
    mkdir -p scripts
    echo '#!/bin/sh' >scripts/build
    ziproj
    expect_rc 0
    expect_in_zip scripts/build
}

test_symlinks_are_stored_not_followed() {
    new_project links
    mkdir -p "$WORK/outside"
    printf 'outside-content-%s\n' "$(rand_alnum 12)" >"$WORK/outside/secret.txt"
    echo 'x' >main.c
    ln -s "$WORK/outside/secret.txt" link.txt
    ziproj
    expect_rc 0
    expect_in_zip main.c link.txt
    unzip -Z "$ZIPFILE" link.txt | grep -q '^l' || fail "link.txt is not stored as a symlink"
    expect_zip_without "outside-content-"
}

test_git_mode_honours_gitignore() {
    new_project gitmode
    mkdir -p Config src
    echo 'x' >src/a.swift
    echo 'API = something-local' >Config/Keys.xcconfig
    printf 'Config/Keys.xcconfig\n' >.gitignore
    echo 'X=1' >.env
    git_repo
    git add -f .env && git commit -qm env >/dev/null 2>&1 # a committed secret file
    echo 'x' >src/untracked.swift
    echo 'x' >src/gone.swift && git add src/gone.swift && git commit -qm gone >/dev/null 2>&1
    rm src/gone.swift # tracked but deleted
    ziproj
    expect_rc 0
    expect_output "[git"
    expect_in_zip src/a.swift src/untracked.swift .gitignore
    expect_not_in_zip Config/Keys.xcconfig .env src/gone.swift
}

test_folder_with_several_repos() {
    new_project workspace
    for r in app-ios app-android; do
        mkdir -p "$r/Config"
        echo 'x' >"$r/main.txt"
        echo 'local' >"$r/Config/Local.xcconfig"
        printf 'Config/Local.xcconfig\n' >"$r/.gitignore"
        git_repo "$r"
    done
    echo 'notes' >README.md
    mkdir -p node_modules/x && echo 'x' >node_modules/x/i.js
    ziproj
    expect_rc 0
    expect_output "2 git repos"
    expect_in_zip README.md app-ios/main.txt app-android/main.txt
    expect_not_in_zip app-ios/Config/Local.xcconfig app-android/Config/Local.xcconfig node_modules/x/i.js
}

test_submodules_are_included() {
    new_project withsub
    mkdir -p "$WORK/lib" && (cd "$WORK/lib" && echo 'lib' >Lib.swift && git_repo .)
    echo 'x' >main.swift
    git_repo
    git -c protocol.file.allow=always submodule add -q "$WORK/lib" Vendor/lib >/dev/null 2>&1
    git commit -qm sub >/dev/null 2>&1
    ziproj
    expect_rc 0
    expect_in_zip main.swift Vendor/lib/Lib.swift
}

test_secret_blocks_and_value_is_never_printed() {
    new_project blocked
    key=$(fake_aws_key)
    printf 'let id = "%s"\n' "$key" >Config.swift
    echo 'x' >main.swift
    ziproj
    expect_rc 1
    expect_no_zip
    expect_output "BLOCKED"
    expect_output "Config.swift:1"
    expect_output "re-run with -r"
    expect_no_output "$key"
}

test_previous_zip_is_removed_when_blocked() {
    new_project stale
    echo 'x' >main.swift
    ziproj
    expect_rc 0
    [ -f "$ZIPFILE" ] || fail "first run did not write a zip"
    printf 'url = "%s"\n' "$(fake_stripe_live)" >Pay.swift
    ziproj
    expect_rc 1
    expect_no_zip
    expect_output "previous stale.zip was removed"
}

test_redact_replaces_values_and_keeps_files_untouched() {
    new_project redact
    key=$(fake_aws_key)
    stripe=$(fake_stripe_live)
    pass=$(rand_alnum 16)
    printf 'let id = "%s"\n' "$key" >Config.swift
    printf 'STRIPE = "%s"\n' "$stripe" >Pay.swift
    printf 'DATABASE_URL=%s://app:%s@db.example.com/app\n' postgres "$pass" >app.yml
    { echo 'let pem = """'; fake_pem; echo '"""'; echo 'let after = 1'; } >Pem.swift
    pem_line=$(sed -n 3p Pem.swift)
    printf '{"private_key":"%s","client_email":"x@example.com"}\n' \
        "$(fake_pem | awk '{printf "%s\\n", $0}')" >service.json
    json_line=$(cut -c40-70 service.json)
    before=$(cat Config.swift Pay.swift app.yml Pem.swift service.json | cksum)
    ziproj -r
    expect_rc 0
    expect_output "secrets redacted in the zip"
    expect_zip_without "$key"
    expect_zip_without "$stripe"
    expect_zip_without "$pass"
    expect_zip_without "$pem_line"
    expect_zip_without "$json_line"
    expect_zip_file_contains Config.swift 'let id = "REDACTED"'
    expect_zip_file_contains Pem.swift 'REDACTED-PRIVATE-KEY'
    expect_zip_file_contains Pem.swift 'let after = 1'
    expect_zip_file_contains service.json '"client_email":"x@example.com"'
    after=$(cat Config.swift Pay.swift app.yml Pem.swift service.json | cksum)
    [ "$before" = "$after" ] || fail "source files were modified"
}

test_dry_run_writes_nothing() {
    new_project dry
    echo 'x' >main.swift
    ziproj -n
    expect_rc 0
    expect_no_zip
    expect_output "dry run, nothing written"
    expect_output "main.swift"
    printf 'k = "%s"\n' "$(fake_aws_key)" >k.swift
    ziproj -n
    expect_rc 1
    expect_no_zip
}

test_ziprojignore_rules() {
    new_project ignore
    mkdir -p docs src/docs fastlane/metadata Tests/Fixtures generated/deep
    for f in docs/a.md src/docs/b.md fastlane/metadata/c.txt generated/deep/d.swift src/main.swift; do
        echo 'x' >"$f"
    done
    printf 'let fixture = "%s"\n' "$(fake_aws_key)" >Tests/Fixtures/token.swift
    printf '# comment\n\n/docs\nfastlane/metadata/\ngenerated\r\nnoscan: Tests/Fixtures\n' >.ziprojignore
    ziproj
    expect_rc 0
    expect_in_zip src/main.swift src/docs/b.md Tests/Fixtures/token.swift
    expect_not_in_zip docs/a.md fastlane/metadata/c.txt generated/deep/d.swift
}

test_global_ignore_file() {
    new_project globalignore
    mkdir -p "$XDG_CONFIG_HOME/ziproj"
    echo 'firebase.json' >"$XDG_CONFIG_HOME/ziproj/ignore"
    echo '{}' >firebase.json
    echo 'x' >main.swift
    ziproj
    rm -f "$XDG_CONFIG_HOME/ziproj/ignore"
    expect_rc 0
    expect_in_zip main.swift
    expect_not_in_zip firebase.json
}

test_exclude_option_and_bundled_flags() {
    new_project excl
    mkdir -p docs assets
    echo 'x' >docs/a.md
    echo 'x' >assets/b.txt
    echo 'x' >main.swift
    ziproj -x docs --exclude=assets
    expect_rc 0
    expect_in_zip main.swift
    expect_not_in_zip docs/a.md assets/b.txt
    ziproj -nxdocs
    expect_rc 0
    expect_no_output "docs/a.md"
}

test_patterns_starting_with_a_dash() {
    new_project dash
    echo 'x' >main.swift
    echo 'x' >-draft.md
    echo 'x' >-notes.txt
    echo '-notes.txt' >.ziprojignore
    ziproj -x -draft.md
    expect_rc 0
    expect_in_zip main.swift
    expect_not_in_zip -draft.md -notes.txt
}

test_ai_mode_drops_media() {
    new_project media
    mkdir -p Assets
    echo 'x' >main.swift
    echo 'x' >Assets/Icon.PNG
    echo 'x' >Assets/photo.jpg
    echo 'x' >Assets/manual.pdf
    echo 'x' >Assets/vector.svg
    ziproj
    expect_in_zip Assets/Icon.PNG Assets/manual.pdf
    ziproj -a
    expect_rc 0
    expect_output ", ai"
    expect_in_zip main.swift Assets/vector.svg
    expect_not_in_zip Assets/Icon.PNG Assets/photo.jpg Assets/manual.pdf
}

test_builtin_patterns_catch_stripe_test_keys() {
    new_project stripetest
    printf 'STRIPE = "sk_%s_%s"\n' test "$(rand_alnum 24)" >Pay.swift
    ziproj
    expect_rc 1
    expect_output "Pay.swift:1"
}

test_force_writes_zip_with_warning() {
    new_project forced
    printf 'k = "%s"\n' "$(fake_aws_key)" >k.swift
    ziproj -f
    expect_rc 0
    expect_in_zip k.swift
    expect_output "possible secrets"
}

test_names_with_spaces_and_unicode() {
    new_project names
    echo 'x' >"My File.swift"
    echo 'x' >"Perché.swift"
    ziproj
    expect_rc 0
    expect_in_zip "My File.swift" "Perché.swift"
}

test_largest_files_are_reported() {
    new_project heavy
    dd if=/dev/zero of=big.bin bs=1024 count=1500 2>/dev/null
    echo 'x' >main.swift
    ziproj
    expect_rc 0
    expect_output "largest files"
    expect_output "big.bin"
}

test_refuses_home_and_missing_paths() {
    new_project guard
    (cd "$HOME" && "$TEST_SHELL" "$ZIPROJ" -n --no-gitleaks) >"$WORK/stdout" 2>"$WORK/stderr" </dev/null
    RC=$?
    expect_rc 1
    expect_output "refusing to zip"
    ziproj_raw -n --no-gitleaks "$WORK/does-not-exist"
    expect_rc 1
    ziproj -o "$WORK/missing-output"
    expect_rc 1
    expect_output "output folder does not exist"
}

test_without_gitleaks_needs_consent() {
    new_project consent
    echo 'x' >main.swift
    (cd "$PROJECT" && ZIPROJ_GITLEAKS=/nonexistent/gitleaks "$TEST_SHELL" "$ZIPROJ" -o "$DEST") \
        >"$WORK/stdout" 2>"$WORK/stderr" </dev/null
    RC=$?
    expect_rc 1
    expect_no_zip
    expect_output "gitleaks is not installed"
    expect_output "--no-gitleaks"
    (cd "$PROJECT" && ZIPROJ_GITLEAKS=/nonexistent/gitleaks "$TEST_SHELL" "$ZIPROJ" -n -o "$DEST") \
        >"$WORK/stdout" 2>"$WORK/stderr" </dev/null
    RC=$?
    expect_rc 0
    expect_output "built-in scan only"
}

test_gitleaks_finds_generic_keys() {
    [ "$HAS_GITLEAKS" = 1 ] || skip "gitleaks not installed"
    new_project gitleaks
    mkdir -p Configurations
    key=$(gitleaks_key) || fail "could not produce a key gitleaks flags"
    printf 'API_KEY = %s\n' "$key" >Configurations/Release.xcconfig
    echo 'x' >main.swift
    ziproj_gitleaks
    expect_rc 1
    expect_output ", gitleaks"
    expect_output "Configurations/Release.xcconfig:1"
}

test_gitleaks_redact_and_verify() {
    [ "$HAS_GITLEAKS" = 1 ] || skip "gitleaks not installed"
    [ "$HAS_JQ" = 1 ] || skip "jq not installed"
    new_project gitleaksredact
    mkdir -p Configurations app
    key=$(gitleaks_key) || fail "could not produce a key gitleaks flags"
    printf 'BASE_URL = api.example.com\nAPI_KEY = %s\n' "$key" >Configurations/Release.xcconfig
    printf 'buildConfigField("String", "API_KEY", "\\"%s\\"")\n' "$key" >app/build.gradle.kts
    long=$(rand_alnum 60)
    printf 'STRIPE = "sk_%s_%s"\n' test "$long" >Pay.swift
    ziproj_gitleaks -r
    expect_rc 0
    expect_zip_without "$key"
    expect_zip_without "$long"
    expect_zip_file_contains Configurations/Release.xcconfig 'API_KEY = REDACTED'
    expect_zip_file_contains Configurations/Release.xcconfig 'BASE_URL = api.example.com'
}

test_project_cannot_switch_gitleaks_off() {
    [ "$HAS_GITLEAKS" = 1 ] || skip "gitleaks not installed"
    new_project gitleaksconfig
    key1=$(gitleaks_key) || fail "could not produce a key gitleaks flags"
    key2=$(gitleaks_key) || fail "could not produce a key gitleaks flags"
    printf 'API_KEY = %s\n' "$key1" >Release.xcconfig
    printf 'API_KEY = %s # gitleaks:%s\n' "$key2" allow >Debug.xcconfig
    printf 'title = "no-op"\n[[rules]]\nid = "noop"\nregex = """zzzzzzzzzzzzzzzzzzzz"""\n' >.gitleaks.toml
    printf 'Release.xcconfig:generic-api-key:1\n' >.gitleaksignore
    ziproj_gitleaks
    expect_rc 1
    expect_output "Release.xcconfig:1"
    expect_output "Debug.xcconfig:1"
    ziproj_gitleaks -r
    expect_rc 0
    expect_zip_without "$key1"
    expect_zip_without "$key2"
    expect_in_zip .gitleaks.toml .gitleaksignore
}

test_gitleaks_report_without_jq() {
    [ "$HAS_GITLEAKS" = 1 ] || skip "gitleaks not installed"
    new_project nojq
    key=$(gitleaks_key) || fail "could not produce a key gitleaks flags"
    printf 'API_KEY = %s\n' "$key" >Release.xcconfig
    (cd "$PROJECT" && ZIPROJ_JQ=/nonexistent/jq "$TEST_SHELL" "$ZIPROJ" -o "$DEST") \
        >"$WORK/stdout" 2>"$WORK/stderr" </dev/null
    RC=$?
    expect_rc 1
    expect_output "Release.xcconfig:1 ("
    (cd "$PROJECT" && ZIPROJ_JQ=/nonexistent/jq "$TEST_SHELL" "$ZIPROJ" -r -o "$DEST") \
        >"$WORK/stdout" 2>"$WORK/stderr" </dev/null
    RC=$?
    expect_rc 1
    expect_output "needs jq"
}

# --------------------------------------------------------------------------
# Runner
# --------------------------------------------------------------------------

# shellcheck disable=SC2016 # $BASH_VERSION is for the child shell
printf 'ziproj tests — shell: %s (%s), gitleaks: %s, jq: %s\n' "$TEST_SHELL" \
    "$("$TEST_SHELL" -c 'echo $BASH_VERSION')" \
    "$([ "$HAS_GITLEAKS" = 1 ] && gitleaks version 2>/dev/null | head -1 || echo no)" \
    "$([ "$HAS_JQ" = 1 ] && echo yes || echo no)"

PASS=0 FAILED=0 SKIPPED=0
FAILED_NAMES=()
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
    case $t in *"$FILTER"*) ;; *) continue ;; esac
    : >"$WORK/stdout"
    : >"$WORK/stderr"
    rm -f "$WORK/skip-reason"
    (cd "$WORK" && "$t") >"$WORK/test.log" 2>&1
    status=$?
    name=${t#test_}
    case $status in
        0)
            PASS=$((PASS + 1))
            printf '  ok    %s\n' "$name"
            ;;
        3)
            SKIPPED=$((SKIPPED + 1))
            printf '  skip  %s (%s)\n' "$name" "$(cat "$WORK/skip-reason" 2>/dev/null)"
            ;;
        *)
            FAILED=$((FAILED + 1))
            FAILED_NAMES+=("$name")
            printf '  FAIL  %s\n' "$name"
            cat "$WORK/test.log"
            ;;
    esac
done

printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAILED" "$SKIPPED"
[ "$FAILED" = 0 ]
