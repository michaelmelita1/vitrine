#!/bin/sh
# Fails when a source file imports across the layers docs/tweaks.md lays out, so what draws on Spotify's screens
# stays apart from what does not: Core <- Settings <- Shared <- Redesigned <- App. Only App imports every layer. Run
# from tweak/Makefile before every build.
#   scripts/check-layers.sh [path to tweak/Sources]
SOURCES=${1:-"$(dirname "$0")/../tweak/Sources"}
cd "$SOURCES" || exit 1
status=0

forbid() {
    layer=$1
    pattern=$2
    [ -d "$layer" ] || return
    hits=$(grep -rnE --include='*.x' --include='*.m' --include='*.h' "#import \"($pattern)/" "$layer")
    if [ -n "$hits" ]; then
        echo "layers: $layer must not import $pattern:" >&2
        echo "$hits" >&2
        status=1
    fi
}

forbid Core "Settings|Shared|Redesigned|App"
forbid Headers "Core|Settings|Shared|Redesigned|App"
forbid Diagnostics "Settings|Shared|Redesigned|App"
forbid Settings "Shared|Redesigned|App"
forbid Shared "Redesigned|App"
forbid Redesigned "App"
exit $status
