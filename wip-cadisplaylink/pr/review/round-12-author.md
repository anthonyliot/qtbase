# Round 12: author's response (qtmultimedia series)

Verdict received: APPROVE (minor 1, nit 3). The series' trees are unchanged in this round (the fixes
are in the scripts and documents), so what's signed is exactly what rounds 11 and 12 reviewed and
round 11's verification tested.

| ID | Response |
|---|---|
| R12-1 minor | **Fixed**: `run-suites.sh` and `verify-states.sh` no longer remove anything. They write to a new `mktemp -d` directory, or to `QTMM_RESULTS` / `QTMM_STATES_LOGS` if set; `run-suites.sh` refuses a directory that exists and isn't empty. |
| R12-2 nit | **Fixed** in `verify-states.sh`: the one-line recovery after a `kill -9` (`git restore --source=<S6> --worktree -- .`) is in its header; the traps are armed after the upfront check; the temporary index is removed; the build is reconfigured after the restore; the warning filter covers every series file; `leak.sh` says so when heap(1) didn't run. The tree construction scripts aren't needed any more: the trees are in the repository, kept by `refs/cadisplaylink/series/S*`. |
| R12-3 nit | **Deferred, recorded**: the test for the else branch (another component setting exactly the window's former value while paused) changes M5's tree, and M5 is revisited after the ProMotion measurement anyway; README "Before sending to Gerrit" and the M5 document list it. |
| R12-4 nits | **Fixed**, except "internal" in the QVideoWidget documentation, which is in M5's tree and deferred with R12-3: README's M5 row and heading, the M5 document's "From", row list, ownership sentence and test list, README step 5's 25 fps file, TESTING's `ab-swap.sh` and the credit to round 12's check of the exact code; the long prose lines wrapped. |

With the built-in ProMotion panel as the only display, README checklist steps 1 to 3 ran (TESTING.md,
"ProMotion panel"): AppKit reports it variable (8.3 to 41.7 ms), `hasVariableRefreshRate()` is true,
`tst_qvideoframebackend` passes on both backends there with `_isOnlySetForVariableRefreshRate`
getting a real preference, and a 24 fps clip plays at 24 frames per second with a preference of
24 on both backends, a 25 fps clip at 25 with none.
