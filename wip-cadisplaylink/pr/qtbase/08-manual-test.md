# 08 Add manual test for display link pacing and frame-rate preferences

| | |
|---|---|
| Commit | `6527194bc72` (qtbase) |
| Files | `tests/manual/displaylink/{CMakeLists.txt,main.cpp}`, `tests/manual/CMakeLists.txt` |
| Plan | Keep; squash 11, 14, 26 into it |

## What
A `QRasterWindow` that animates continuously and shows its update rate next to its screen's refresh
rate, with keys to switch frame-rate presets and open more windows.

## Why
To check pacing and smoothness by eye and with Instruments, and (after 11) for scripted
measurements (`bench/video-rates.sh`, `bench/panel-rate-ab.sh`).

## Risks
Builds on every platform (it only uses QWindow API and a dynamic property). License: see 14.

## Verify
`qt5-build-cadisplaylink/tests/manual/displaylink/displaylink.app` (`--help` lists the options).
