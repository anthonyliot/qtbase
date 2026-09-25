#!/bin/sh
# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: BSD-3-Clause
# Restore the wip/cadisplaylink work on another machine.
#
# The branch lives in the qtbase submodule of the qt5 superproject. Before running this, the
# branch must be published somewhere reachable, either:
#   a) pushed to a remote:        (in qtbase) git push <remote> wip/cadisplaylink
#   b) exported as a bundle:      (in qtbase) git bundle create ~/cadisplaylink.bundle origin/dev..wip/cadisplaylink
#                                 then copy the .bundle file to the other machine.
#
# Usage:
#   restore.sh <remote-url-or-bundle-path> [qt5-checkout-dir] [build-dir]
#
# Example:
#   ./restore.sh git@github.com:<you>/qtbase.git ~/src/qt5 ~/src/qt5-build-cadisplaylink
#   ./restore.sh ~/cadisplaylink.bundle
set -e

SOURCE="$1"
QT5_DIR="${2:-$HOME/qt5}"
BUILD_DIR="${3:-$QT5_DIR-build-cadisplaylink}"
BRANCH=wip/cadisplaylink
# qtbase commit the branch was started from (for reference / bundle prerequisite)
BASE=25d8223e59f

if [ -z "$SOURCE" ]; then
    sed -n '4,19p' "$0"; exit 1
fi

if [ ! -d "$QT5_DIR/.git" ]; then
    git clone https://code.qt.io/qt/qt5.git "$QT5_DIR"
fi
cd "$QT5_DIR"
git submodule update --init qtbase
cd qtbase
git fetch origin
git cat-file -e "$BASE^{commit}" 2>/dev/null || git fetch origin dev

git fetch "$SOURCE" "$BRANCH:$BRANCH"
git switch "$BRANCH"
git log --oneline "$BASE..$BRANCH"

# Configure a developer build (tests on demand) and build what the work needs.
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
GEN="Unix Makefiles"; command -v ninja >/dev/null && GEN=Ninja
cmake -G "$GEN" "$QT5_DIR/qtbase" -DFEATURE_developer_build=ON -DQT_BUILD_TESTS=ON \
      -DQT_BUILD_TESTS_BY_DEFAULT=OFF -DQT_BUILD_MANUAL_TESTS=ON -DQT_BUILD_EXAMPLES=OFF \
      -DCMAKE_BUILD_TYPE=Debug -DFEATURE_sql=OFF
cmake --build . --parallel --target QCocoaIntegrationPlugin tst_qwindow tst_qappleframerate displaylink

cat <<EOF

Restored. Next steps:
  $BUILD_DIR/tests/auto/gui/platform/qappleframerate/tst_qappleframerate
  $BUILD_DIR/tests/auto/gui/kernel/qwindow/tst_qwindow
  open $BUILD_DIR/tests/manual/displaylink/displaylink.app

iOS simulator build (optional, uses the build above as host):
  see the "Verification" section in $QT5_DIR/qtbase/wip-cadisplaylink/PLAN.md

Claude context for resuming: $QT5_DIR/qtbase/wip-cadisplaylink/CLAUDE-NOTES.md
EOF
