#!/bin/zsh
# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: BSD-3-Clause
#
# Measures the display panel's actual refresh rate (xctrace Display instrument vsyncs) while
# cool-retro-term animates, with the old (CVDisplayLink) and new (CADisplayLink) cocoa plugin and
# different preferred frame rates. Meaningful on variable refresh panels (ProMotion); keep the
# machine idle, as anything else animating on screen raises the panel rate.
#
# Usage: panel-rate-ab.sh [trials] [variant:fps ...]   (default: 2 trials of old:, old:60, new:, new:60, new:30)
set -u
TRIALS=${1:-2}
CONFIGS=("${@:2}")
(( ${#CONFIGS} )) || CONFIGS=(old: old:60 new: new:60 new:30)
HERE=${0:A:h}
BB=${BB:-/Users/anthony.liot/Desktop/bitbucket}
QT=$BB/qt5-build-nofw
BIN="$BB/cool-retro-term/build-nofw/cool-retro-term.app/Contents/MacOS/cool-retro-term"
PLUGIN=$QT/plugins/platforms/libqcocoa_debug.dylib
VARIANTS=/tmp/qtab-nofw
OUT=${OUT:-/tmp/panel-ab}
mkdir -p $OUT
[[ -x /tmp/qt-bench-tools/zorder ]] || swiftc -O $HERE/zorder.swift -o /tmp/qt-bench-tools/zorder

run() { # variant env-fps trial
    local v=$1 fps=$2 trial=$3 tag="$1-${2:-default}-$3"
    cp $VARIANTS/$v/platforms/libqcocoa_debug.dylib $PLUGIN
    local want=$(grep "^$v " $VARIANTS/uuids.txt | awk '{print $2}')
    local -a envs=(DYLD_PRINT_LIBRARIES=1)
    [[ -n $fps ]] && envs+=(QT_APPLE_PREFERRED_FRAME_RATE_RANGE=$fps)
    env $envs "$BIN" > $OUT/$tag.log 2>&1 &
    local P=$!
    sleep 10   # KDSingleApplication waits 5 s when its local socket is unavailable
    local got=$(grep -m1 libqcocoa $OUT/$tag.log | grep -oE '<[^>]+>' | tr -d '<>')
    if [[ $got != $want ]]; then echo "$tag: UUID mismatch"; kill $P; return; fi
    if ! /tmp/qt-bench-tools/zorder $P | grep -q "z-index 1,"; then
        echo "$tag: window not frontmost/on screen, skipping"; kill $P; return
    fi
    rm -rf $OUT/$tag.trace
    xcrun xctrace record --instrument 'Display' --all-processes --time-limit 5s --output $OUT/$tag.trace > /dev/null 2>&1
    kill $P; wait $P 2>/dev/null
    echo "$tag: $(python3 $HERE/vsync_rates.py $OUT/$tag.trace | grep -i built-in)"
}

for trial in $(seq 1 $TRIALS); do
    for c in $CONFIGS; do run ${c%%:*} "${c#*:}" $trial; done
done
cp $VARIANTS/new/platforms/libqcocoa_debug.dylib $PLUGIN
# Baseline: nothing of ours running
rm -rf $OUT/idle.trace; xcrun xctrace record --instrument 'Display' --all-processes --time-limit 5s --output $OUT/idle.trace > /dev/null 2>&1
echo "idle (no app): $(python3 $HERE/vsync_rates.py $OUT/idle.trace | grep -i built-in)"
