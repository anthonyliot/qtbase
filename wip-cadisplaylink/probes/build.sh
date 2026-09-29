#!/bin/sh
# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: BSD-3-Clause
# Build and run the standalone AppKit CADisplayLink probes (no Qt needed).
set -e
cd "$(dirname "$0")"
for p in probe valid divisors; do
    clang++ -fobjc-arc -x objective-c++ -std=c++17 -framework AppKit -framework QuartzCore $p.m -o /tmp/qt-dl-$p
done
/tmp/qt-dl-valid
/tmp/qt-dl-probe
/tmp/qt-dl-divisors
