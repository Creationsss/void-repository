#!/bin/sh
set -u

VP="${VP:-/void-packages}"
REPO="${REPO:-$GITHUB_WORKSPACE}"
OUT="${OUT:-/tmp/autoupdate-result}"
IGNORE_FILE="${IGNORE_FILE:-$REPO/.github/autoupdate-ignore}"
J="$(nproc 2>/dev/null || echo 1)"

: > "$OUT"
[ -x "$VP/xbps-src" ] && [ -d "$VP/srcpkgs" ] || { echo "fatal: $VP is not a void-packages clone"; exit 2; }
[ -d "$REPO/srcpkgs" ] || { echo "fatal: $REPO/srcpkgs missing"; exit 2; }
cd "$VP" || exit 2

tmpl() { echo "$VP/srcpkgs/$1/template"; }
field() { sed -n "s/^$2=//p" "$(tmpl "$1")" | head -1; }

listed_ignore() {
    [ -f "$IGNORE_FILE" ] || return 1
    while IFS= read -r pat; do
        case "$pat" in ''|\#*) continue ;; esac
        case "$1" in $pat) return 0 ;; esac
    done < "$IGNORE_FILE"
    return 1
}

ineligible() {
    listed_ignore "$1" && return 0
    [ "$(field "$1" _no_autoupdate)" = "yes" ] && return 0
    return 1
}

version_ignored() (
    _p="$1"; _v="$2"
    set -f
    [ -f "$IGNORE_FILE" ] || exit 1
    while IFS= read -r line; do
        case "$line" in ''|\#*) continue ;; esac
        lp="${line%% *}"
        [ "$lp" = "$line" ] && continue
        case "$_p" in $lp) ;; *) continue ;; esac
        for g in ${line#* }; do
            case "$_v" in $g) exit 0 ;; esac
        done
    done < "$IGNORE_FILE"
    exit 1
)

revert() { mv "$1.orig" "$1"; }

newest() {
    timeout 90 ./xbps-src update-check "$1" 2>/dev/null \
        | sed -n "s/.* -> $1-\(.*\)\$/\1/p" \
        | { while IFS= read -r v; do version_ignored "$1" "$v" || echo "$v"; done; } \
        | sort -V | tail -1
}

kde_newest() {
    base="https://download.kde.org/stable/release-service"
    for v in $(curl -fsS --max-time 30 "$base/" 2>/dev/null \
        | grep -oE '[0-9]{2}\.[0-9]{2}\.[0-9]+' | sort -Vru); do
        { [ "$(printf '%s\n%s\n' "$2" "$v" | sort -V | tail -1)" = "$v" ] && [ "$v" != "$2" ]; } || break
        curl -fsIL --max-time 20 "$base/$v/src/$1-$v.tar.xz" >/dev/null 2>&1 && { echo "$v"; return; }
    done
}

updated=0
for d in "$REPO"/srcpkgs/*/; do
    name="$(basename "$d")"
    [ -L "$REPO/srcpkgs/$name" ] && continue
    [ -f "$(tmpl "$name")" ] || continue
    ineligible "$name" && continue

    cur="$(field "$name" version)"
    rev="$(field "$name" revision)"
    t="$(tmpl "$name")"
    cp "$t" "$t.orig"
    hook="$(dirname "$t")/autoupdate"
    if [ -f "$hook" ]; then
        new="$(TEMPLATE="$t" CURRENT="$cur" sh "$hook" 2>/dev/null)"
        [ -n "$new" ] || { rm -f "$t.orig"; continue; }
    elif [ -n "$(field "$name" _kde_project)" ]; then
        new="$(kde_newest "$name" "$cur")"
        [ -n "$new" ] || { rm -f "$t.orig"; continue; }
    else
        new="$(newest "$name")"
        { [ -n "$new" ] && [ "$new" != "$cur" ]; } || { rm -f "$t.orig"; continue; }
    fi

    echo ":: $name: $cur -> $new (trying)"
    sed -i "s/^version=.*/version=$new/;s/^revision=.*/revision=1/" "$t"

    if ! timeout 300 xgensum -i -f "$t" >/tmp/xg-"$name".log 2>&1; then
        echo "   checksum/fetch failed -> revert"; revert "$t"; continue
    fi
    if [ "$(sed -n 's/^checksum=//p' "$t")" = "$(sed -n 's/^checksum=//p' "$t.orig")" ]; then
        echo "   distfile unchanged by version bump (commit-pinned?) -> skip"; revert "$t"; continue
    fi
    if ! ./xbps-src -j"$J" pkg "$name" >/tmp/build-"$name".log 2>&1; then
        if grep -q '/void-packages/xbps-src' /tmp/build-"$name".log; then
            echo "   masterdir corrupted -> zap + rebootstrap + retry"
            ./xbps-src zap >/dev/null 2>&1 || true
            ./xbps-src binary-bootstrap >/dev/null 2>&1 || true
            [ -x /usr/local/bin/bun ] && cp /usr/local/bin/bun masterdir-x86_64/usr/bin/bun 2>/dev/null || true
        fi
        if ! ./xbps-src -j"$J" pkg "$name" >/tmp/build-"$name".log 2>&1; then
            echo "   build failed -> revert (see /tmp/build-$name.log)"; revert "$t"; continue
        fi
    fi

    rm -f "$t.orig"
    cp -f "$t" "$REPO/srcpkgs/$name/template"
    echo "$name ${cur}_${rev} ${new}_1" >> "$OUT"
    echo "   ok: $name $cur -> $new"
    updated=$((updated + 1))
done

echo ":: $updated package(s) updated"
exit 0
