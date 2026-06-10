#!/bin/sh
set -eu

pkglist=""

for pkg in "$GITHUB_WORKSPACE"/srcpkgs/*/; do
    [ -L "${pkg%/}" ] && continue
    name="$(basename "$pkg")"
    ver="$(sed -n 's/^version=//p' "$pkg/template")"
    rev="$(sed -n 's/^revision=//p' "$pkg/template")"
    desc="$(sed -n 's/^short_desc="\(.*\)"/\1/p' "$pkg/template")"
    dist="$(sed -n '/^distfiles=/{s/^distfiles="//;s/"$//;p;q}' "$pkg/template")"
    no_vcheck="$(sed -n 's/^_no_vcheck=//p' "$pkg/template")"

    api="github"
    api_url=""
    repo=""
    tag_prefix=""

    kde_project="$(sed -n 's/^_kde_project="\(.*\)"/\1/p' "$pkg/template")"
    vcheck_repo="$(sed -n 's/^_vcheck_repo="\(.*\)"/\1/p' "$pkg/template")"
    vcheck_tag_prefix="$(sed -n 's/^_vcheck_tag_prefix="\(.*\)"/\1/p' "$pkg/template")"
    build="$(sed -n 's/^_build=//p' "$pkg/template")"
    check_ver="$ver"
    if [ -n "$build" ]; then
        check_ver="${ver}-${build}"
    fi

    if [ -n "$vcheck_repo" ]; then
        repo="$vcheck_repo"
        api="github-tags"
        [ -n "$vcheck_tag_prefix" ] && tag_prefix="$vcheck_tag_prefix"
    elif [ -n "$kde_project" ]; then
        api="gitlab"
        api_url="https://invent.kde.org"
        repo="$kde_project"
        tag_prefix="v"
    elif echo "$dist" | grep -q 'github\.com'; then
        repo="$(echo "$dist" | sed -n 's|.*github\.com/\([^/]*/[^/]*\)/.*|\1|p')"
    elif echo "$dist" | grep -q 'codeberg\.org'; then
        api="codeberg"
        repo="$(echo "$dist" | sed -n 's|.*codeberg\.org/\([^/]*/[^/]*\)/.*|\1|p')"
    elif echo "$dist" | grep -q 'heliopolis\.live'; then
        api="gitea"
        api_url="https://void-proxy.creations.works"
        repo="$(echo "$dist" | sed -n 's|.*heliopolis\.live/\([^/]*/[^/]*\)/.*|\1|p')"
    fi

    vcheck_api="$(sed -n 's/^_vcheck_api="\(.*\)"/\1/p' "$pkg/template")"
    vcheck_url="$(sed -n 's/^_vcheck_url="\(.*\)"/\1/p' "$pkg/template")"
    if [ -n "$vcheck_api" ]; then
        api="$vcheck_api"
        repo="$name"
        [ -n "$vcheck_url" ] && api_url="$vcheck_url"
    fi

    if echo "$dist" | grep -q "release_candidate_\${version}\|release_candidate_${ver}"; then
        tag_prefix="release_candidate_"
    elif echo "$dist" | grep -q "desktop-v\${version}\|desktop-v${ver}"; then
        tag_prefix="desktop-v"
    elif echo "$dist" | grep -q "@[^@]*@\${version}\|@[^@]*@${ver}"; then
        tag_prefix="$(echo "$dist" | sed -n 's|.*\(@[^@]*@\)\${version}.*|\1|p')"
        [ -z "$tag_prefix" ] && tag_prefix="$(echo "$dist" | sed -n 's|.*\(@[^@]*@\)'"${ver}"'.*|\1|p')"
    elif echo "$dist" | grep -q "v\${version}\|v${ver}\|tags/v"; then
        tag_prefix="v"
    fi

    if [ "$no_vcheck" = "yes" ]; then
        attrs=""
    else
        attrs="data-repo='${repo}' data-version='${check_ver}' data-tag-prefix='${tag_prefix}' data-api='${api}'"
        if [ -n "$api_url" ]; then
            attrs="${attrs} data-api-url='${api_url}'"
        fi
    fi

    pkglist="${pkglist}<span class='pkg' ${attrs}>  ${name} ${ver}_${rev} - ${desc}</span>"
done

cp "$GITHUB_WORKSPACE/index.html" /void-packages/hostdir/binpkgs/index.html
printf '%s\n' "$pkglist" > /tmp/pkglist.html
sed -i '/<!-- PACKAGES -->/{r /tmp/pkglist.html
d
}' /void-packages/hostdir/binpkgs/index.html
