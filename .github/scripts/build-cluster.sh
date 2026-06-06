#!/bin/sh
set -eu

cd /void-packages

if [ "${BUILD_ONLY:-}" = "__none__" ]; then
    echo ":: Filter resolved to no packages"
    mkdir -p /tmp/built-xbps
    exit 0
fi

pkgs=""
for p in $CLUSTER_PKGS; do
    if [ -n "${BUILD_ONLY:-}" ]; then
        case " $BUILD_ONLY " in *" $p "*) pkgs="$pkgs $p" ;; esac
    else
        pkgs="$pkgs $p"
    fi
done
pkgs="$(echo "$pkgs" | xargs)"

if [ -z "$pkgs" ]; then
    echo ":: Nothing to build in cluster $CLUSTER_NAME"
    mkdir -p /tmp/built-xbps
    exit 0
fi

sorted="$(./xbps-src sort-dependencies $pkgs 2>/dev/null || echo "$pkgs")"
echo ":: Build order: $sorted"

mkdir -p /tmp/built-xbps
touch /tmp/build-start
failed=""

for pkgname in $sorted; do
    for suffix in "" "-devel" "-dbg" "-doc" "-libs" "-32bit"; do
        rm -f hostdir/binpkgs/${pkgname}${suffix}-[0-9]*.xbps \
              hostdir/binpkgs/${pkgname}${suffix}-[0-9]*.xbps.sig2
    done
    echo ":: Building $pkgname..."
    if ./xbps-src -j"$(nproc)" pkg "$pkgname"; then
        echo ":: $pkgname built"
    else
        echo "::warning::Failed to build $pkgname (continuing)"
        failed="$failed $pkgname"
        echo ":: Re-bootstrapping masterdir after failure..."
        ./xbps-src zap
        ./xbps-src binary-bootstrap
        cp /usr/local/bin/bun masterdir-x86_64/usr/bin/bun
    fi
done

find hostdir/binpkgs -maxdepth 1 -name '*.xbps' -newer /tmp/build-start \
    -exec cp -t /tmp/built-xbps {} +
ls /tmp/built-xbps | sed 's/^/  -> /'

if [ -n "$failed" ]; then
    echo "::warning::cluster $CLUSTER_NAME failed: $failed"
fi
