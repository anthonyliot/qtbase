#!/bin/zsh
# ab-swap.sh <set>: install an artifact set (the Multimedia and MultimediaQuick libraries and both
# media plugins, saved in $AB_DIR/<set>/) into qt5-build-nofw, and check it. qtmm-build writes its
# libraries there, so an upstream A/B swaps these files instead of using a second build. To make
# the sets: copy the four files after building the series ("series"), and after building
# qtmm-build from upstream 635067497's sources put in the worktree ("upstream"; README).
AB=${AB_DIR:-${TMPDIR:-/tmp}/qtmm-ab}
Q=${QT_PREFIX:-${QT5_REPO:-/Users/anthony.liot/Desktop/bitbucket/qt5}/../qt5-build-nofw}
ART=(lib/libQt6Multimedia_debug.6.13.0.dylib lib/libQt6MultimediaQuick_debug.6.13.0.dylib plugins/multimedia/libdarwinmediaplugin_debug.dylib plugins/multimedia/libffmpegmediaplugin_debug.dylib)
for a in $ART; do cp -p $AB/$1/${a:t} $Q/$a || exit 1; done
for a in $ART; do cmp -s $AB/$1/${a:t} $Q/$a || { echo "SWAP FAILED ${a:t}"; exit 1; }; done
echo "installed: $1"
