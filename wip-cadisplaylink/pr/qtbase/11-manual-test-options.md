# 11 displaylink manual test: Add options for automated measurements

| | |
|---|---|
| Commit | `f48f930cd3c` (qtbase) |
| Files | `tests/manual/displaylink/main.cpp` |
| Plan | Squash into 08 |

## What
`--log` (rate, frames, refresh rate, size, exposure, update request/expose counts every 250 ms),
`--preset`, `--position`, `--pause-after`, `--quit-after`, `--busy-ms`, `--on-top`.

## Why
Scripted A/B measurements (`bench/*.sh`), and telling occlusion stalls (Qt stops painting
unexposed windows) apart from display link issues.
