#!/bin/zsh
# leak.sh <label>: the leak probe (20 players with autorelease pools), built on first use against
# the Qt of qt5-build-nofw; prints the live DisplayLinkObserver and CADisplayLink counts.
HERE=${0:A:h}; P=${HERE:h:h:h}/probes/qtmultimedia/leakprobe
Q=${QT_PREFIX:-${QT5_REPO:-/Users/anthony.liot/Desktop/bitbucket/qt5}/../qt5-build-nofw}
if [[ ! -x $P/build/leakprobe ]]; then
  cmake -S $P -B $P/build -DCMAKE_PREFIX_PATH=$Q -DCMAKE_BUILD_TYPE=Debug > /dev/null && cmake --build $P/build > /dev/null || { echo "leak probe build failed"; exit 1; }
fi
$P/count.sh $1 20 pools 2>/dev/null
# heap(1) lists no line for a class with no live object, so check that it did run
grep -q "ObjC classes" $P/build/$1.heap || echo "leak probe: heap(1) didn't run, see $P/build/$1.heap"
