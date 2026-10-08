# bash completion for ziproj - https://github.com/carmelogallo/ziproj
# Works with bash 3.2 (macOS) and newer.

_ziproj() {
    local cur prev IFS=$'\n'
    cur=${COMP_WORDS[COMP_CWORD]}
    prev=${COMP_WORDS[COMP_CWORD - 1]}

    # shellcheck disable=SC2207 # mapfile is not available in bash 3.2
    case $prev in
        -o | --out)
            COMPREPLY=($(compgen -d -- "$cur"))
            return 0
            ;;
        -x | --exclude)
            COMPREPLY=($(compgen -f -- "$cur"))
            return 0
            ;;
    esac

    # shellcheck disable=SC2207
    if [[ $cur == -* ]]; then
        COMPREPLY=($(IFS=$' \t\n' compgen -W '-n --dry-run -r --redact -a --ai -x --exclude
            -o --out -f --force --no-gitleaks --no-open -h --help -V --version' -- "$cur"))
    else
        COMPREPLY=($(compgen -d -- "$cur"))
    fi
}

complete -o filenames -F _ziproj ziproj
