#!/bin/sh
set -u

WS="${GITHUB_WORKSPACE:-.}"
VERSIONS="${VERSIONS:-versions.json}"
OUTDIR="${OUTDIR:-/void-packages/hostdir/binpkgs}"

status_html() {
    [ -f "$VERSIONS" ] || return 0
    jq -r --arg n "$1" '
        .packages[$n] as $p
        | if $p == null then ""
          elif $p.status == "ok" then " <span class=\"ver-ok\">[up to date]</span>"
          elif $p.status == "rolling" then " <span class=\"ver-ok\">[rolling]</span>"
          elif $p.status == "update" and (($p.latest // "") != "") then
            " <span class=\"ver-update\">[" + $p.latest + " available]</span>"
          elif $p.status == "error" then " <span class=\"ver-error\">[?]</span>"
          else "" end' "$VERSIONS" 2>/dev/null
}

pkglist=""
for pkg in "$WS"/srcpkgs/*/; do
    if [ -L "${pkg%/}" ]; then continue; fi
    name="$(basename "$pkg")"
    ver="$(sed -n 's/^version=//p' "$pkg/template")"
    rev="$(sed -n 's/^revision=//p' "$pkg/template")"
    desc="$(sed -n 's/^short_desc="\(.*\)"/\1/p' "$pkg/template")"
    st="$(status_html "$name")"

    pkglist="${pkglist}<span class='pkg' data-pkg='${name}'>  ${name} ${ver}_${rev} - ${desc}${st}</span>"
done

mkdir -p "$OUTDIR"
cp "$WS/index.html" "$OUTDIR/index.html"
printf '%s\n' "$pkglist" > /tmp/pkglist.html
sed -i '/<!-- PACKAGES -->/{r /tmp/pkglist.html
d
}' "$OUTDIR/index.html"
