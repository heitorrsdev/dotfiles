#!/usr/bin/env bash
#
# Pushes the current branch, merges it into a target branch and switches back.
#
# Usage:
#   git-this-to.sh [target] [-p|--push]
#
# Examples:
#   git-this-to.sh              # merges the current branch into dev
#   git-this-to.sh homolog -p   # merges into homolog and pushes homolog
#
# Notes:
#   - The default target is 'dev'.
#   - Aborts if there are uncommitted changes to tracked files.
#   - The target is updated with pull --ff-only before the merge.
#   - The target is pushed only with --push.
#   - On merge conflict, stops on the target branch so the conflict can be resolved.

set -uo pipefail

usage() {
    echo "Usage: $(basename "$0") [target] [-p|--push]" >&2
    exit 2
}

target=''
push_target=0

while (($#)); do
    case "$1" in
        -p | --push)
            push_target=1
            shift
            ;;
        -h | --help | -*) usage ;;
        *)
            [[ -z "$target" ]] || usage
            target="$1"
            shift
            ;;
    esac
done

target="${target:-dev}"

if [[ -t 1 ]]; then
    cyan=$'\033[0;36m' green=$'\033[0;32m' yellow=$'\033[0;33m' red=$'\033[0;31m' nc=$'\033[0m'
else
    cyan='' green='' yellow='' red='' nc=''
fi

step() {
    printf '%s→ %s%s\n' "$cyan" "$*" "$nc"
}

fail() {
    printf '%s✗ %s%s\n' "$red" "$*" "$nc" >&2
    exit 1
}

# Switches back to the source branch and fails with the given message.
return_and_fail() {
    git switch --quiet "$source" || fail "$* (could not switch back to '$source')"
    fail "$*"
}

git rev-parse --is-inside-work-tree &>/dev/null || fail 'not inside a git repository'

source=$(git branch --show-current)
[[ -n "$source" ]] || fail 'detached HEAD: switch to a branch first'
[[ "$source" != "$target" ]] || fail "already on '$target'"

[[ -z "$(git status --porcelain --untracked-files=no)" ]] || fail 'uncommitted changes: commit or stash them first'

git fetch --prune origin || fail 'fetch failed'
git show-ref --verify --quiet "refs/heads/$target" ||
    git show-ref --verify --quiet "refs/remotes/origin/$target" ||
    fail "branch '$target' does not exist locally nor on origin"

step "pushing '$source'"
if git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' &>/dev/null; then
    git push || fail "push of '$source' failed"
else
    git push --set-upstream origin "$source" || fail "push of '$source' failed"
fi

step "switching to '$target'"
git switch "$target" || fail "switch to '$target' failed"

step "updating '$target'"
git pull --ff-only || return_and_fail "pull of '$target' failed"

step "merging '$source' into '$target'"
if ! git merge --no-edit "$source"; then
    printf '\n%s! Merge conflict: still on '\''%s'\''.%s\n' "$yellow" "$target" "$nc"
    printf '  Resolve the conflicts, run git commit, then git switch %s\n' "$source"
    exit 1
fi

if ((push_target)); then
    step "pushing '$target'"
    git push || return_and_fail "push of '$target' failed"
fi

step "switching back to '$source'"
git switch "$source" || fail "switch back to '$source' failed"

printf '%s✓ %s merged into %s%s\n' "$green" "$source" "$target" "$nc"
