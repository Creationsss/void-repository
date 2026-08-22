#!/bin/sh
set -u

WS="${GITHUB_WORKSPACE:-.}"
VERSIONS="${VERSIONS:-versions.json}"
OUTDIR="${OUTDIR:-/void-packages/hostdir/binpkgs}"

CAT_ORDER="Hyprland Discord Gaming Media Peripherals Apps Libraries"

field() {
    v="$(sed -n "s/^$2=//p" "$1" | head -1)"
    v="${v#\"}"
    v="${v%\"}"
    printf '%s' "$v"
}

meta_of() {
    [ -f "$VERSIONS" ] || { printf 'none\t'; return; }
    jq -r --arg n "$1" '
        (.packages[$n]) as $p
        | (($p.status) // "none") as $s
        | $s + "\t" + (
            if $p == null then ""
            elif $s == "rolling" then "<span class=\"badge neutral\">rolling</span>"
            elif $s == "update" and (($p.latest // "") != "") then
              "<span class=\"badge update\">" + $p.latest + " available</span>"
            elif $s == "error" then "<span class=\"badge unknown\">unknown</span>"
            else "" end
          )' "$VERSIONS" 2>/dev/null
}

in_order() {
    for c in $CAT_ORDER; do [ "$c" = "$1" ] && return 0; done
    return 1
}

TAB="$(printf '\t')"
ROWS="$(mktemp)"
trap 'rm -f "$ROWS"' EXIT

for pkg in "$WS"/srcpkgs/*/; do
    [ -L "${pkg%/}" ] && continue
    t="$pkg/template"
    name="$(basename "$pkg")"
    ver="$(field "$t" version)"
    rev="$(field "$t" revision)"
    desc="$(field "$t" short_desc)"
    cat="$(field "$t" _category)"
    if [ -z "$cat" ]; then
        cat="Other"
    elif ! in_order "$cat"; then
        echo "::warning::$name has _category=$cat not in CAT_ORDER; bucketed as Other" >&2
        cat="Other"
    fi

    meta="$(meta_of "$name")"
    st="${meta%%$TAB*}"
    badge="${meta#*$TAB}"

    row="<div class='pkg' data-pkg='${name}' data-status='${st}' data-cat='${cat}'><div class='pkg-info'><div class='pkg-row'><span class='name'>${name}</span><span class='ver'>${ver}_${rev}</span></div><div class='desc'>${desc}</div></div><span class='dl' data-pkg='${name}'></span>${badge}</div>"
    printf '%s\t%s\n' "$cat" "$row" >> "$ROWS"
done

pkglist=""
for cat in $CAT_ORDER Other; do
    group="$(awk -F"$TAB" -v c="$cat" '$1==c{sub(/^[^\t]*\t/,""); print}' "$ROWS")"
    [ -z "$group" ] && continue
    count="$(printf '%s\n' "$group" | wc -l | tr -d ' ')"
    rows="$(printf '%s' "$group" | tr -d '\n')"
    pkglist="${pkglist}<div class='cat-head' data-cat='${cat}'>${cat} <span class='cat-n'>${count}</span></div>${rows}"
done

mkdir -p "$OUTDIR"
cp "$WS/index.html" "$OUTDIR/index.html"
printf '%s\n' "$pkglist" > /tmp/pkglist.html
sed -i '/<!-- PACKAGES -->/{r /tmp/pkglist.html
d
}' "$OUTDIR/index.html"
