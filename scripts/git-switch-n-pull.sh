#!/usr/bin/env bash
#
# Switches every repository in the folder to a branch and updates it with pull.
#
# Usage:
#   git-switch-n-pull.sh <branch> [-p|--path <folder>] [-i|--ignore <repo>]...
#
# Examples:
#   git-switch-n-pull.sh homolog
#   git-switch-n-pull.sh homolog -p ~/back -i core -i out
#
# Notes:
#   - core is never switched (default of --ignore; passing --ignore replaces the default).
#   - Without --path, uses the current directory.
#   - Repositories with local changes are skipped, so no work is lost.
#   - Repositories without the branch stay on their current branch.
#   - pull uses --ff-only: never creates a merge. If the branch diverged from origin, it is reported as a failure.
#   - Exits with code 1 if any repository fails.

set -uo pipefail

usage() {
    echo "Usage: $(basename "$0") <branch> [-p|--path <folder>] [-i|--ignore <repo>]..." >&2
    exit 2
}

branch=''
path='.'
ignore=()

while (($#)); do
    case "$1" in
        -p | --path)
            [[ $# -ge 2 ]] || usage
            path="$2"
            shift 2
            ;;
        -i | --ignore)
            [[ $# -ge 2 ]] || usage
            ignore+=("$2")
            shift 2
            ;;
        -h | --help) usage ;;
        -*) usage ;;
        *)
            [[ -z "$branch" ]] || usage
            branch="$1"
            shift
            ;;
    esac
done

[[ -n "$branch" ]] || usage
((${#ignore[@]})) || ignore=('core')

if [[ -t 1 ]]; then
    declare -A colors=(
        ['OK']=$'\033[0;32m'
        ['NO PULL']=$'\033[0;33m'
        ['NO BRANCH']=$'\033[0;33m'
        ['SKIPPED']=$'\033[0;33m'
        ['FAILED']=$'\033[0;31m'
    )
    cyan=$'\033[0;36m'
    red=$'\033[0;31m'
    nc=$'\033[0m'
else
    declare -A colors=()
    cyan='' red='' nc=''
fi

# Runs git in the repository; the output (stdout + stderr) is stored in $output.
invoke_git() {
    local repo="$1"
    shift
    output=$(git -C "$repo" "$@" 2>&1)
}

last_line() {
    printf '%s\n' "$1" | sed '/^[[:space:]]*$/d' | tail -n 1
}

# Sets $result and $detail.
update_repository() {
    local repo="$1" output before local_ok=0 remote_ok=0

    if ! invoke_git "$repo" status --porcelain; then
        result='FAILED' detail=$(last_line "$output")
        return
    fi
    if [[ -n "$output" ]]; then
        result='SKIPPED' detail='has local changes'
        return
    fi

    if ! invoke_git "$repo" fetch --prune origin; then
        result='FAILED' detail="fetch: $(last_line "$output")"
        return
    fi

    invoke_git "$repo" show-ref --verify --quiet "refs/heads/$branch" && local_ok=1
    invoke_git "$repo" show-ref --verify --quiet "refs/remotes/origin/$branch" && remote_ok=1
    if ((!local_ok && !remote_ok)); then
        result='NO BRANCH' detail='does not exist locally nor on origin'
        return
    fi

    if ! invoke_git "$repo" switch "$branch"; then
        result='FAILED' detail="switch: $(last_line "$output")"
        return
    fi

    if ((!remote_ok)); then
        result='NO PULL' detail='branch exists only locally'
        return
    fi

    invoke_git "$repo" rev-parse HEAD
    before="$output"
    if ! invoke_git "$repo" pull --ff-only; then
        result='FAILED' detail="pull: $(last_line "$output")"
        return
    fi

    invoke_git "$repo" rev-parse HEAD
    if [[ "$output" == "$before" ]]; then
        result='OK' detail='already up to date'
    else
        result='OK' detail='updated with pull'
    fi
}

repos=()
for dir in "$path"/*/; do
    [[ -d "$dir" ]] || continue
    dir="${dir%/}"
    name="${dir##*/}"
    for ign in "${ignore[@]}"; do
        [[ "$name" == "$ign" ]] && continue 2
    done
    [[ -e "$dir/.git" ]] && repos+=("$dir")
done

if ((${#repos[@]} == 0)); then
    echo "${red}No repositories found in $path${nc}"
    exit 1
fi

printf '%sSwitching %d repositories to '\''%s'\''%s\n\n' "$cyan" "${#repos[@]}" "$branch" "$nc"

declare -A count=()
order=()
failed=0

for repo in "${repos[@]}"; do
    update_repository "$repo"
    invoke_git "$repo" branch --show-current
    current="$output"

    printf '%s%-10s %-28s [%s] %s%s\n' "${colors[$result]:-}" "$result" "${repo##*/}" "$current" "$detail" "$nc"

    [[ -n "${count[$result]:-}" ]] || order+=("$result")
    count[$result]=$((${count[$result]:-0} + 1))
    [[ "$result" == 'FAILED' ]] && failed=1
done

echo
for r in "${order[@]}"; do
    printf '%s%-10s %d%s\n' "${colors[$r]:-}" "$r" "${count[$r]}" "$nc"
done

exit "$failed"
