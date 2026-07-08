#!/bin/sh
export APPDIR=/usr/lib/goverlay
export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-pulseaudio}"
exec /usr/lib/goverlay/bin/goverlay "$@"
