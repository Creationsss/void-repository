#!/bin/sh
set -eu

cd /void-packages/hostdir/binpkgs

for xbps in *.xbps; do
    [ -f "$xbps" ] || continue
    pkgver="$(echo "${xbps%.xbps}" | sed 's/\.[a-zA-Z0-9_]*$//')"
    pkgname="$(xbps-uhelper getpkgname "$pkgver" 2>/dev/null)" || {
        echo ":: skip malformed $xbps"
        continue
    }
    base="$pkgname"
    for suffix in -devel -dbg -doc -libs -32bit; do
        base="${base%$suffix}"
    done
    if [ ! -d "$GITHUB_WORKSPACE/srcpkgs/$pkgname" ] && [ ! -d "$GITHUB_WORKSPACE/srcpkgs/$base" ]; then
        echo ":: Removing stale: $xbps"
        rm -f "$xbps" "${xbps}.sig" "${xbps}.sig2"
    fi
done
