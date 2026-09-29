# qtdeclarative 06 tst_qquickanimations: Expect only frame rates the display link supports

| | |
|---|---|
| Commit | `d57406c0b8` (qtdeclarative) |
| Files | `tst_qquickanimations.cpp` |
| Plan | Squash into 05 |

## What
The expected step for 30 fps uses the rule of qtbase 30: the largest n dividing the whole refresh
rate with `refresh / n >= 29.7`.
