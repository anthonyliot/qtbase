#!/bin/zsh
# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: BSD-3-Clause
#
# A/B benchmark of Qt Quick Effect Maker with the old (CVDisplayLink) and new (CADisplayLink)
# cocoa platform plugin, swapped into the same Qt build (the loaded binary's UUID is verified).
#
# Before running:
#  - be on a normal desktop Space (not a full-screen app), with the 240 Hz display as main display
#  - don't use the machine for ~8 minutes: the "playing" runs click the Play button once (only if
#    nothing covers it), and Qt stops rendering windows that are hidden or covered
#
# Usage: qqem-ab.sh [trials]      (default 3)
# Needs: ../qt5-build-nofw (qtbase, no frameworks) + qtdeclarative + qtshadertools + qtquickeffectmaker
#        built into it, and /tmp/qtab-nofw/{old,new}/platforms/libqcocoa_debug.dylib + uuids.txt
set -u
zmodload zsh/datetime
TRIALS=${1:-3}
HERE=${0:A:h}
BB=${BB:-/Users/anthony.liot/Desktop/bitbucket}
QT=$BB/qt5-build-nofw
BIN="$QT/bin/Qt Quick Effect Maker.app/Contents/MacOS/Qt Quick Effect Maker"
QEP=$BB/qt5/qtquickeffectmaker/examples/quickeffectmaker/wiggly/WigglyEffect/WigglyEffect.qep
PLUGIN=$QT/plugins/platforms/libqcocoa_debug.dylib
VARIANTS=/tmp/qtab-nofw
OUT=${OUT:-/tmp/qqem-ab}
PLAY_X=1182 PLAY_Y=260   # Play button, in window coordinates (window 1200x832 incl. title bar)
mkdir -p $OUT /tmp/qt-bench-tools

for t in rusage safeclick zorder; do
    [[ /tmp/qt-bench-tools/$t -nt $HERE/$t.swift ]] || swiftc -O $HERE/$t.swift -o /tmp/qt-bench-tools/$t || exit 1
done

run() { # variant scenario env-fps trial
    local v=$1 scenario=$2 fps=$3 trial=$4 tag="$1-$2-${3:-default}-$4"
    cp $VARIANTS/$v/platforms/libqcocoa_debug.dylib $PLUGIN
    local want=$(grep "^$v " $VARIANTS/uuids.txt | awk '{print $2}')
    local -a envs=(QT_MESSAGE_PATTERN="%{time process} %{category} %{message}"
                   QT_LOGGING_RULES="qt.scenegraph.time.renderloop.debug=true" DYLD_PRINT_LIBRARIES=1)
    [[ -n $fps ]] && envs+=(QT_APPLE_PREFERRED_FRAME_RATE_RANGE=$fps)
    local launched=$EPOCHREALTIME
    env $envs "$BIN" "$QEP" > $OUT/$tag.log 2>&1 &
    local P=$!
    sleep 6
    local got=$(grep -m1 libqcocoa $OUT/$tag.log | grep -oE '<[^>]+>' | tr -d '<>')
    if [[ $got != $want ]]; then echo "$tag: UUID mismatch ($got vs $want)"; kill $P; return; fi
    if ! /tmp/qt-bench-tools/zorder $P | grep -q "z-index 1,"; then
        echo "$tag: window not frontmost/on screen, skipping"; kill $P; return
    fi
    if [[ $scenario == playing ]]; then
        /tmp/qt-bench-tools/safeclick $P $PLAY_X $PLAY_Y > /dev/null || { echo "$tag: Play not clickable"; kill $P; return; }
        sleep 2
    fi
    # Measurement window, in seconds since launch (process time in the log), skipping the first second
    local from=$(( EPOCHREALTIME - launched + 1 ))
    /tmp/qt-bench-tools/rusage $P 10 > $OUT/$tag.rusage
    kill $P; wait $P 2>/dev/null
    python3 - "$tag" $OUT/$tag.log $OUT/$tag.rusage $from <<'EOF'
import re, sys
tag, log, ru, frm = sys.argv[1:]
frm = float(frm)
rows = [dict(re.findall(r'(\w+)=([\d.]+)', l)) for l in open(ru) if l.startswith('s=')]
rows = rows[1:]  # skip the first second
avg = lambda k: sum(float(r[k]) for r in rows) / max(1, len(rows))
times = [float(l.split()[0]) for l in open(log) if 'frame rendered' in l]
fps = sum(1 for t in times if frm <= t < frm + 9) / 9
print(f"{tag}|{fps:.1f}|{avg('cpu'):.1f}|{avg('intw'):.0f}|{avg('energy_mW'):.1f}")
EOF
}

: > $OUT/results.txt
for trial in $(seq 1 $TRIALS); do
    for v in old new; do
        run $v idle "" $trial >> $OUT/results.txt
        run $v playing "" $trial >> $OUT/results.txt
        run $v playing 60 $trial >> $OUT/results.txt
    done
    run new playing 30 $trial >> $OUT/results.txt
done
cp $VARIANTS/new/platforms/libqcocoa_debug.dylib $PLUGIN   # leave the new plugin installed

python3 - $OUT/results.txt <<'EOF'
import collections, sys
agg = collections.OrderedDict(); skipped = []
for line in open(sys.argv[1]):
    if '|' not in line: skipped.append(line.strip()); continue
    tag, fps, cpu, intw, mw = line.strip().split('|')
    key = tag.rsplit('-', 1)[0]
    agg.setdefault(key, []).append((float(fps), float(cpu), float(intw), float(mw)))
print(f"{'variant-scenario-env':32} {'n':>2} {'fps':>6} {'CPU %':>6} {'wakeups/s':>9} {'energy mW':>9}")
for k, xs in agg.items():
    n = len(xs); m = lambda i: sum(x[i] for x in xs) / n
    print(f"{k:32} {n:>2} {m(0):6.1f} {m(1):6.1f} {m(2):9.0f} {m(3):9.1f}")
for s in skipped: print("skipped:", s)
EOF
