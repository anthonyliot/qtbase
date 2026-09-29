# 05 Doc: Refer to CADisplayLink instead of CVDisplayLink

| | |
|---|---|
| Commit | `ad8e1183c91` (qtbase) |
| Files | `examples/gui/rhiwindow/rhiwindow.cpp`, `src/gui/rhi/qrhi.cpp`, `tests/manual/graphicsframecapture/window.cpp`, `tests/manual/rhi/hellominimalcrossgfxtriangle/window.cpp` |
| Plan | Keep |

## What
Comments and the QRhi overview doc now say update requests are backed by CADisplayLink on macOS and
iOS (the QRhi doc linked the CVDisplayLink reference page).

## Why
They described the old implementation.

## Verify
`git grep -n CVDisplayLink` in qtbase only finds historical comments in `qcocoascreen.mm`
("Unlike CVDisplayLink...") and the WIP notes.
