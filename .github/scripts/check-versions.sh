#!/bin/sh
set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
: "${GH_TOKEN:=$(gh auth token 2>/dev/null || true)}"
export GH_TOKEN

out="$(mktemp)"
trap 'rm -f "$out"' EXIT

GITHUB_WORKSPACE="$root" OUT="$out" sh "$root/.github/scripts/gen-versions.sh" 2>/dev/null

printf '%-28s %-18s %-18s %s\n' PACKAGE CURRENT LATEST STATUS
printf '%-28s %-18s %-18s %s\n' '-------' '-------' '------' '------'
jq -r '
    .packages | to_entries
    | sort_by(.value.status == "update" or .value.status == "error" | not)
    | .[] | [.key, .value.current, (.value.latest // "-"), .value.status] | @tsv
' "$out" | while IFS="$(printf '\t')" read -r n c l s; do
    printf '%-28s %-18s %-18s %s\n' "$n" "$c" "$l" "$s"
done

echo
echo "updates: $(jq '[.packages[]|select(.status=="update")]|length' "$out") · errors: $(jq '[.packages[]|select(.status=="error")]|length' "$out") · total: $(jq '.packages|length' "$out")"
