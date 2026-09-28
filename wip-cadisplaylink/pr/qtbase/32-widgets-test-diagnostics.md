# 32 tst_QWidgetRepaintManager: Report the rates when resetting the rate fails

| | |
|---|---|
| Commit | see `git log --grep "Report the rates when resetting"` (qtbase) |
| Files | `tests/auto/widgets/kernel/qwidgetrepaintmanager/tst_qwidgetrepaintmanager.cpp` |
| Plan | Squash into 24 |

## What
After resetting the preference, `pacedUpdates` skips if the window got covered and reports the
measured rates on failure.

## Why
It failed once in a full run on the 240 Hz display without saying why; 14 reruns passed. Qt stops
rendering covered windows, which the check didn't account for.
