# qtdeclarative 04 Only set the frame interval on the default animation driver

| | |
|---|---|
| Commit | `23ce107427` (qtdeclarative) |
| Files | `qsgcontext.cpp` |
| Plan | Squash into 01 |

## What
`setFrameIntervalForAnimationDriver()` uses `qobject_cast<QSGDefaultAnimationDriver *>` instead of
an unconditional `static_cast<QSGAnimationDriver *>`.

## Why
`QSGContext::createAnimationDriver()` is virtual; a subclass may return a driver that isn't a
`QSGAnimationDriver`, so the cast was undefined behavior.
