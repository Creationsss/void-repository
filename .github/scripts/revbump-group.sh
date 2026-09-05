#!/bin/sh
set -eu

group="${1:-}"
[ -n "$group" ] || { echo "usage: revbump-group.sh <group-name>"; exit 2; }

cd "$(git rev-parse --show-toplevel)"

bumped=""
for d in srcpkgs/*/; do
    [ -L "${d%/}" ] && continue
    t="${d}template"
    [ "$(sed -n 's/^_rebuild_group=//p' "$t" | head -1)" = "$group" ] || continue
    name="$(basename "$d")"
    rev="$(sed -n 's/^revision=//p' "$t" | head -1)"
    new=$((rev + 1))
    sed -i "s/^revision=${rev}\$/revision=${new}/" "$t"
    bumped="${bumped} ${name}(${rev}->${new})"
done

[ -n "$bumped" ] && echo "revbumped:${bumped}" || { echo "no packages in _rebuild_group=${group}"; exit 1; }
echo "now bump the provider's version, then commit with the group bracketed."
