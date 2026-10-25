#!/bin/sh
lib=/usr/lib/millennium
steam="${HOME}/.steam/steam"

if [ "$(id -u)" -eq 0 ]; then
	echo "run millennium-setup as your normal user, not root" >&2
	exit 1
fi

link() {
	mkdir -p "$(dirname "$2")"
	ln -sf "$1" "$2"
	echo "linked $2 -> $1"
}

unlink_ours() {
	case "$(readlink "$1" 2>/dev/null)" in
	"$lib"/*) rm -f "$1" && echo "removed $1" ;;
	esac
}

case "${1:-install}" in
install)
	link "$lib/libmillennium_bootstrap_x86.so" "$steam/ubuntu12_32/libXtst.so.6"
	link "$lib/libmillennium_bootstrap_hhx64.so" "$steam/ubuntu12_64/libXtst.so.6"
	link "$lib/libmillennium_hhx64.so" "$steam/ubuntu12_64/libmillennium_hhx64.so"
	if [ -f "$steam/package/beta" ]; then
		echo "note: Steam beta is enabled ($(cat "$steam/package/beta")), Millennium targets the stable client"
	fi
	echo "done, restart Steam"
	;;
remove)
	unlink_ours "$steam/ubuntu12_32/libXtst.so.6"
	unlink_ours "$steam/ubuntu12_64/libXtst.so.6"
	unlink_ours "$steam/ubuntu12_64/libmillennium_hhx64.so"
	;;
*)
	echo "usage: millennium-setup [install|remove]" >&2
	exit 1
	;;
esac
