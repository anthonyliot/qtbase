# 20 cocoa: Update the live resize event tap comment for CADisplayLink

| | |
|---|---|
| Commit | `5cf2ecde754` (qtbase) |
| Files | `qcocoascreen.mm` |
| Plan | Squash into 03 |

## What
The comment above the live-resize event tap referred to the GCD source; it now says the tap is
kept for the CADisplayLink run loop source but hasn't been re-validated (a FIXME).

## Why
Keeping a workaround whose reason no longer matches the code without saying so is misleading.
Synthetic live-resize tests showed no difference without it, but real mouse live resize wasn't
tested.
