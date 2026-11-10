#!/bin/sh
# This helper belongs to the menu-bar app, never to launchd.
# If the GUI is force-quit, remove its SSH child as well.
owner=$1
shift
"$@" &
ssh_pid=$!
guardian=$$
watcher=
cleanup() {
    trap '' TERM INT HUP
    [ -z "$watcher" ] || kill "$watcher" 2>/dev/null || :
    kill "$ssh_pid" 2>/dev/null || :
    wait "$ssh_pid" 2>/dev/null || :
}
trap 'cleanup; exit 0' TERM INT HUP
(
    while kill -0 "$owner" 2>/dev/null && kill -0 "$guardian" 2>/dev/null; do
        sleep 2
    done
    kill "$ssh_pid" 2>/dev/null || :
    kill "$guardian" 2>/dev/null || :
) &
watcher=$!
wait "$ssh_pid"
result=$?
cleanup
exit "$result"
