# 26 displaylink manual test: Add --rate and --trace

| | |
|---|---|
| Commit | `a92aa4ade7c` (qtbase) |
| Files | `tests/manual/displaylink/{CMakeLists.txt,main.cpp}` |
| Plan | Squash into 08 (the series needs 22 first) |

## What
`--rate <fps>` sets `QWindow::preferredFrameRate`; `--trace` records the last update request,
expose and paint events and prints them with the exposure and pending-request state at exit (to
catch an intermittent stall that wasn't root-caused, VIDEO.md). Links `Qt::GuiPrivate` for the
pending-request state.
