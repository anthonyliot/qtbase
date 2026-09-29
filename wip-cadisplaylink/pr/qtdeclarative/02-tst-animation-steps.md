# qtdeclarative 02 tst_qquickanimations: Test animation steps with a preferred frame rate

| | |
|---|---|
| Commit | `b7a304f21c` (qtdeclarative) |
| Files | `tests/auto/quick/qquickanimations/{tst_qquickanimations.cpp,data/preferredFrameRate.qml}` |
| Plan | Keep |
| Later changed by | 03, 05, 06 |

## What
`stepsWithPreferredFrameRate`: a NumberAnimation in a window paced at 30 fps must advance by the
paced frame interval per frame (e.g. 33.3 units at 30 fps on 120/240 Hz), measured over 1 s with
a real event loop, skipping the first frames. Skipped off cocoa/ios and without the threaded render
loop.

## Verify
Without 01, on 240 Hz the steps are 4.17 instead of 33.3 (`without-fix-qquickanimations.txt` in
the nofw qtdeclarative build dir).
