#!/bin/sh
# Force XWayland on Wayland sessions (orbolay needs X11 input grab)
if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
	unset WAYLAND_DISPLAY
fi
exec /usr/lib/orbolay/orbolay "$@"
