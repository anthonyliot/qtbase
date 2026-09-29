# G1 tst_QWindow: Test the rate and delivery of update requests

| | |
|---|---|
| Repo, branch | qtbase `wip/cadisplaylink-gerrit` |
| Files | `tests/auto/gui/kernel/qwindow/tst_qwindow.cpp` |
| From | old 07 and 19, the parts that don't need new API |

## What
Helpers (`AnimatingWindow`, `measureUpdateRates()` with a real event loop and retry,
`unthrottledRate()`, `QCOMPARE_RATE*`) and 5 tests: `requestUpdateRate` (continuous requests at the
link's rate, on the main thread), `requestUpdateMultipleWindows`, `requestUpdateCreatedButHidden`,
`requestUpdateAfterHideAndShow`, `requestUpdateSwapIntervalZero` (timer based).

## Why first
They pin down what the CVDisplayLink implementation provides, and must pass before and after G2
(no regression, request #4). Display-paced tests skip on platforms other than cocoa/ios.

The display link doesn't report its interval at G1 (the old plugin can't), so a window without a
preference may get anything from half the refresh rate to the refresh rate (`unthrottledRates()`),
as the system can lower it without telling (Low Power Mode). From G2 on it's the link's reported
rate. The retry uses half the refresh rate when no interval is reported (R2-2).

## Verified
At G1, i.e. with the old CVDisplayLink plugin: TESTING.md, series section.
