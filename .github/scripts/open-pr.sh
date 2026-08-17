#!/bin/sh
set -eu

RESULT="${RESULT:-/tmp/autoupdate-result}"
BRANCH="${BRANCH:-autoupdate}"
WS="${GITHUB_WORKSPACE:-$(pwd)}"
OWNER="${GITHUB_REPOSITORY%%/*}"
API="https://api.github.com/repos/${GITHUB_REPOSITORY}"

[ -s "$RESULT" ] || { echo ":: no updates, nothing to open"; exit 0; }

title=""
body=""
while read -r name old new status; do
    [ -n "$name" ] || continue
    title="${title}[${name}]"
    if [ "$status" = buildfail ]; then
        body="${body}- ${name}: ${old} -> ${new}  (BUILD FAILED)\\n"
    else
        body="${body}- ${name}: ${old} -> ${new}\\n"
    fi
done < "$RESULT"

cd "$WS"
git config --global --add safe.directory "$WS"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git fetch -q origin "$BRANCH" 2>/dev/null || true
git checkout -B "$BRANCH"
git add srcpkgs
git diff --cached --quiet && { echo ":: nothing staged, skipping"; exit 0; }
git commit -m "$title" -m "$(printf '%b' "$body")"

if git rev-parse -q --verify "origin/$BRANCH" >/dev/null 2>&1 &&
   [ "$(git rev-parse 'HEAD^{tree}')" = "$(git rev-parse "origin/${BRANCH}^{tree}")" ]; then
    echo ":: branch unchanged since last run, skipping push and pr"
    exit 0
fi
git push -f origin "HEAD:refs/heads/${BRANCH}"

num="$(curl -fsS -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "${API}/pulls?head=${OWNER}:${BRANCH}&state=open" \
    | sed -n 's/.*"number": *\([0-9]\+\).*/\1/p' | head -1)"

if [ -n "$num" ]; then
    echo ":: updating existing pr #$num"
    curl -fsS -X PATCH -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "${API}/pulls/${num}" \
        -d "$(printf '{"title":"%s","body":"%s"}' "$title" "$body")" >/dev/null
else
    echo ":: opening new pr"
    curl -fsS -X POST -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "${API}/pulls" \
        -d "$(printf '{"title":"%s","body":"%s","base":"main","head":"%s"}' "$title" "$body" "$BRANCH")" >/dev/null
fi
echo ":: done"
