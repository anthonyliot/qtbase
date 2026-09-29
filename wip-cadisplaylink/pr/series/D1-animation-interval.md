# D1 Advance vsync based animations by the window's frame interval

| | |
|---|---|
| Repo, branch | qtdeclarative `wip/cadisplaylink-gerrit` |
| Files | `src/quick/scenegraph/{qsgcontext.cpp,qsgcontext_p.h,qsgthreadedrenderloop.cpp}`, `tests/auto/quick/qquickanimations/{tst_qquickanimations.cpp,data/preferredFrameRate.qml,data/preferredFrameRateAnimator.qml}` |
| From | old qtdeclarative 01-04, 06, and the Animator test fixes (settle, skip when covered) |
| Depends on | qtbase G4 (interval), G5 (for the tests to be paced) |

See the old qtdeclarative 01 and 03 docs. Tests: `stepsWithPreferredFrameRate`,
`animatorDurationWithPreferredFrameRate`.

## Verified
Built against the qtbase series head (non-framework build of the same tree); see TESTING.md.
