#!/bin/sh
set -eu

RESULT="${RESULT:-/tmp/autoupdate-result}"
WS="${GITHUB_WORKSPACE:-$(pwd)}"
LOGDIR="${LOGDIR:-/tmp}"
API="https://api.github.com/repos/${GITHUB_REPOSITORY}"

[ -s "$RESULT" ] || { echo ":: no updates, nothing to do"; exit 0; }

cd "$WS"
git config --global --add safe.directory "$WS"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

gh_get() {
    curl -fsS -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github+json" "${API}$1"
}

issue_open() {
    gh_get "/issues?state=open&per_page=100" \
        | jq -e --arg t "$1" 'any(.[]; .title == $t)' >/dev/null 2>&1
}

open_issue() {
    if issue_open "$1"; then
        echo ":: issue already open: $1"
        return 0
    fi
    curl -fsS -X POST -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github+json" "${API}/issues" \
        -d "$(jq -n --arg t "$1" --rawfile b "$2" '{title:$t, body:$b}')" >/dev/null
    echo ":: opened issue: $1"
}

title=""
body=""
oks=0
fails=0

while read -r name old new status; do
    [ -n "$name" ] || continue
    if [ "$status" = buildfail ]; then
        fails=$((fails + 1))
        git checkout -- "srcpkgs/$name/template" 2>/dev/null || true
        bf="$(mktemp)"
        {
            printf 'Auto-update build-verify failed for `%s` (%s -> %s).\n' "$name" "$old" "$new"
            printf 'The bump was reverted and not pushed, so main still builds.\n\n'
            printf 'Last lines of the build log:\n\n'
            printf '```\n'
            tail -n 40 "$LOGDIR/build-$name.log" 2>/dev/null || printf '(build log unavailable)\n'
            printf '```\n'
        } > "$bf"
        open_issue "autoupdate: $name failed to build ($new)" "$bf"
        rm -f "$bf"
    else
        oks=$((oks + 1))
        title="${title}[${name}]"
        body="${body}- ${name}: ${old} -> ${new}
"
        git add "srcpkgs/$name/template"
    fi
done < "$RESULT"

if [ "$oks" -gt 0 ] && ! git diff --cached --quiet; then
    git commit -m "$title" -m "$body"

    key="${DEPLOY_KEY_FILE:-$HOME/.ssh/deploy_key}"
    [ -f "$key" ] || { echo "::error::deploy key $key missing; cannot push"; exit 1; }
    export GIT_SSH_COMMAND="ssh -i $key -o StrictHostKeyChecking=accept-new"
    remote="git@github.com:${GITHUB_REPOSITORY}.git"

    git push "$remote" HEAD:main || {
        echo ":: push rejected, rebasing on origin/main and retrying"
        git fetch "$remote" main
        git rebase FETCH_HEAD
        git push "$remote" HEAD:main
    }
    echo ":: pushed $oks update(s) to main"
else
    echo ":: no successful updates to push"
fi
