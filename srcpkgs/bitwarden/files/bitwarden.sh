#!/bin/sh
ulimit -c 0

if [ "$XDG_SESSION_TYPE" = "wayland" ] && [ "$USE_X11" != "true" ]; then
	PARAMS="--enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform-hint=auto"
else
	PARAMS="--ozone-platform=x11"
fi

exec /usr/lib/bitwarden/bitwarden-app $PARAMS "$@"
