#!/bin/zsh
# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: BSD-3-Clause
#
# For a list of requested frame rates (video content rates by default), measures the rate Qt delivers
# update requests at (tests/manual/displaylink) and the panel's actual refresh rate (xctrace Display
# vsyncs) at the same time. Meant for variable refresh (ProMotion) panels; keep the machine idle.
#
# Usage: video-rates.sh [rate ...]
set -u
HERE=${0:A:h}
BB=${BB:-/Users/anthony.liot/Desktop/bitbucket}
APP=${APP:-$BB/qt5-build-cadisplaylink/tests/manual/displaylink/displaylink.app/Contents/MacOS/displaylink}
OUT=${OUT:-/tmp/video-rates}
mkdir -p $OUT
RATES=("$@")
(( ${#RATES} )) || RATES=(default 23.976 24 25 29.97 30 40 48 50 59.94 60 80 120)
zmodload zsh/datetime
printf "%-8s %12s %12s %10s  %s\n" requested "delivered" "during-trace" panel "panel intervals by nearest rate"
for r in $RATES; do
    local -a envs=()
    [[ $r != default ]] && envs=(QT_APPLE_PREFERRED_FRAME_RATE_RANGE=$r)
    local launched=$EPOCHREALTIME
    env $envs $APP --log --on-top --position 300,200 --quit-after 30 > $OUT/$r.log 2>&1 &
    local P=$!
    sleep 4
    local traceStart=$(( EPOCHREALTIME - launched ))
    rm -rf $OUT/$r.trace
    # xctrace occasionally hangs; give up on it after 30 s
    xcrun xctrace record --instrument 'Display' --all-processes --time-limit 5s --output $OUT/$r.trace > /dev/null 2>&1 &
    local X=$!
    for i in {1..30}; do kill -0 $X 2>/dev/null || break; sleep 1; done
    kill -0 $X 2>/dev/null && { kill -INT $X; sleep 2; kill $X 2>/dev/null; }
    wait $X 2>/dev/null
    local traceEnd=$(( EPOCHREALTIME - launched ))
    kill $P; wait $P 2>/dev/null
    local rates=$(python3 - $OUT/$r.log $traceStart $traceEnd <<'PY'
import re, sys
rows = [(float(t), int(f)) for t, f in re.findall(r"t=([\d.]+) rate=[\d.]+ frames=(\d+)", open(sys.argv[1]).read())]
ts, te = float(sys.argv[2]), float(sys.argv[3])
def rate(a, b):
    w = [f for t, f in rows if a < t <= b]
    return f"{sum(w) / (len(w) * 0.25):.2f}" if w else "n/a"
# before the trace (skipping startup), and during the trace (skipping xctrace's own startup)
print(rate(1.5, ts), rate(ts + 2, te))
PY
)
    local panel=$(python3 $HERE/vsync_rates.py $OUT/$r.trace 2>/dev/null | grep -i built-in | sed -E 's/.*= ([0-9.]+) Hz average; intervals by nearest rate: (.*)/\1 Hz|\2/')
    [[ -z $panel ]] && panel="n/a|(trace failed)"
    printf "%-8s %12s %12s %10s  %s\n" $r ${rates%% *} ${rates##* } "${panel%%|*}" "${panel#*|}"
done
