#!/bin/sh
set -u

SRCDIR="${GITHUB_WORKSPACE:-.}/srcpkgs"
OUT="${OUT:-versions.json}"
UA="void-repo-version-checker"

gh() {
	if [ -n "${GH_TOKEN:-}" ]; then
		curl -fsSL --max-time 30 -H "User-Agent: $UA" \
			-H "Accept: application/vnd.github+json" \
			-H "Authorization: Bearer ${GH_TOKEN}" "$1"
	else
		curl -fsSL --max-time 30 -H "User-Agent: $UA" \
			-H "Accept: application/vnd.github+json" "$1"
	fi
}

plain() { curl -fsSL --max-time 30 -H "User-Agent: $UA" "$1"; }

field() {
	v="$(sed -n "s/^$2=//p" "$1" | head -1)"
	v="${v#\"}"
	v="${v%\"}"
	printf '%s' "$v"
}

strip_latest() {
	tag="$1"
	prefix="$2"
	case "$prefix" in
		"") ;;
		*) case "$tag" in "$prefix"*) tag="${tag#"$prefix"}" ;; esac ;;
	esac
	printf '%s' "$tag" | sed 's/-[A-Za-z]\{1,\}$//'
}

KDE_BASE="https://download.kde.org/stable/release-service"

kde_pick() {
	for v in $(grep -oE '[0-9]{2}\.[0-9]{2}\.[0-9]+' | sort -Vru); do
		{ [ "$(printf '%s\n%s\n' "$2" "$v" | sort -V | tail -1)" = "$v" ] && [ "$v" != "$2" ]; } || break
		curl -fsIL --max-time 20 -H "User-Agent: $UA" "$KDE_BASE/$v/src/$1-$v.tar.xz" >/dev/null 2>&1 && { echo "$v"; return; }
	done
}

pick_tag() {
	jq -r --arg p "$prefix" --arg ig "$vcheck_ignore" '
		[.[].name | select(index("/") | not)
			| select($ig == "" or (test($ig) | not))
			| select($p == "" or startswith($p))][0] // empty' 2>/dev/null
}

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

for d in "$SRCDIR"/*/; do
	[ -L "${d%/}" ] && continue
	t="${d}template"
	[ -f "$t" ] || continue
	name="$(basename "$d")"

	[ "$(field "$t" _no_vcheck)" = "yes" ] && continue
	[ -f "${d}autoupdate" ] && continue

	ver="$(sed -n 's/^version=//p' "$t" | head -1)"
	build="$(sed -n 's/^_build=//p' "$t" | head -1)"
	current="$ver"
	[ -n "$build" ] && current="${ver}-${build}"

	kde_project="$(field "$t" _kde_project)"
	if [ -n "$kde_project" ]; then
		kde_list="$(plain "$KDE_BASE/" 2>/dev/null)"
		if [ -z "$kde_list" ]; then
			latest=""; status="error"
		else
			latest="$(printf '%s' "$kde_list" | kde_pick "$name" "$ver")"
			[ -z "$latest" ] && latest="$ver"
			[ "$latest" = "$ver" ] && status="ok" || status="update"
		fi
		printf '%s\t%s\t%s\t%s\n' "$name" "$current" "$latest" "$status" >> "$tmp"
		echo ":: ${name}: current=${current} latest=${latest:-?} (${status}) [kde]" >&2
		continue
	fi

	dist="$(sed -n '/^distfiles=/{s/^distfiles="//;s/"$//;p;q}' "$t")"
	vcheck_repo="$(field "$t" _vcheck_repo)"
	vcheck_tag_prefix="$(field "$t" _vcheck_tag_prefix)"
	vcheck_ignore="$(field "$t" _vcheck_ignore)"
	vcheck_api="$(field "$t" _vcheck_api)"
	vcheck_url="$(field "$t" _vcheck_url)"

	api="github"
	api_url=""
	repo=""
	prefix=""

	if [ -n "$vcheck_repo" ]; then
		repo="$vcheck_repo"
		api="github-tags"
		[ -n "$vcheck_tag_prefix" ] && prefix="$vcheck_tag_prefix"
	elif echo "$dist" | grep -q 'github\.com'; then
		repo="$(echo "$dist" | sed -n 's|.*github\.com/\([^/]*/[^/]*\)/.*|\1|p')"
	elif echo "$dist" | grep -q 'codeberg\.org'; then
		api="codeberg"
		repo="$(echo "$dist" | sed -n 's|.*codeberg\.org/\([^/]*/[^/]*\)/.*|\1|p')"
	elif echo "$dist" | grep -q 'heliopolis\.live'; then
		api="gitea"
		api_url="https://heliopolis.live"
		repo="$(echo "$dist" | sed -n 's|.*heliopolis\.live/\([^/]*/[^/]*\)/.*|\1|p')"
	fi

	if [ -n "$vcheck_api" ]; then
		api="$vcheck_api"
		[ -z "$vcheck_repo" ] && repo="$name"
		[ -n "$vcheck_url" ] && api_url="$vcheck_url"
	fi

	case "$dist" in
		*release_candidate_'${version}'*|*"release_candidate_${ver}"*) prefix="release_candidate_" ;;
		*desktop-v'${version}'*|*"desktop-v${ver}"*) prefix="desktop-v" ;;
		*v'${version}'*|*"v${ver}"*|*tags/v*) [ -z "$prefix" ] && prefix="v" ;;
	esac

	latest=""
	status="error"

	if [ "$api" = "rolling" ]; then
		printf '%s\t%s\t%s\t%s\n' "$name" "$current" "" "rolling" >> "$tmp"
		continue
	fi
	[ -z "$repo" ] && { printf '%s\t%s\t%s\t%s\n' "$name" "$current" "" "skip" >> "$tmp"; continue; }

	case "$api" in
		labymod)
			ft="${prefix:-LAUNCHER}"
			latest="$(plain "https://laby.net/api/v3/changelog" 2>/dev/null | jq -r --arg t "$ft" 'map(select(.type==$t))[0].version // empty' 2>/dev/null || true)"
			;;
		wooting)
			wurl="$(printf '%s' "${dist%%>*}" | sed 's/[?&]version=[^&]*//')"
			loc="$(curl -sS -o /dev/null -D - --max-time 30 -H "User-Agent: $UA" "$wurl" 2>/dev/null | awk 'tolower($1)=="location:"{print $2}' | tr -d '\r')"
			latest="$(printf '%s' "$loc" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
			;;
		gh-branch)
			date="$(gh "https://api.github.com/repos/${repo}/branches/${prefix:-main}" 2>/dev/null | jq -r '.commit.commit.committer.date // empty' 2>/dev/null || true)"
			[ -n "$date" ] && latest="0.0.0.$(printf '%s' "$date" | cut -c1-10 | tr -d '-')"
			;;
		gitea)
			latest="$(plain "${api_url}/api/v1/repos/${repo}/tags" 2>/dev/null | pick_tag)"
			;;
		codeberg)
			latest="$(plain "https://codeberg.org/api/v1/repos/${repo}/releases/latest" 2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null || true)"
			;;
		github-tags)
			latest="$(gh "https://api.github.com/repos/${repo}/tags" 2>/dev/null | pick_tag)"
			;;
		*)
			case "$prefix" in
				desktop-v*)
					latest="$(gh "https://api.github.com/repos/${repo}/releases" 2>/dev/null \
						| jq -r --arg p "$prefix" --arg ig "$vcheck_ignore" '
							[.[].tag_name | select($ig=="" or (test($ig)|not))
								| select(startswith($p))][0] // empty' 2>/dev/null || true)"
					;;
				*)
					latest="$(gh "https://api.github.com/repos/${repo}/releases" 2>/dev/null \
						| jq -r --arg ig "$vcheck_ignore" '
							[.[] | select(.prerelease|not) | .tag_name
								| select(index("/")|not)
								| select($ig=="" or (test($ig)|not))][0] // empty' 2>/dev/null || true)"
					;;
			esac
			;;
	esac

	if [ -n "$latest" ]; then
		latest="$(strip_latest "$latest" "$prefix")"
		[ "$latest" = "$current" ] && status="ok" || status="update"
	fi

	printf '%s\t%s\t%s\t%s\n' "$name" "$current" "$latest" "$status" >> "$tmp"
	echo ":: ${name}: current=${current} latest=${latest:-?} (${status})" >&2
done

jq -R -s '
	split("\n") | map(select(length > 0)) | map(split("\t"))
	| map({(.[0]): {current: .[1], latest: .[2], status: .[3]}}) | add // {}
' "$tmp" | jq '{packages: .}' > "$OUT"

echo ":: wrote $OUT with $(jq '.packages | length' "$OUT") packages" >&2
