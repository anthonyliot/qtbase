# Round 3 review: the committed Gerrit series

Reviewer: independent, round 3. Scope: the signed Gerrit series, reviewed commit by commit as a
Gerrit reviewer would, plus re-verification that the round-2 findings (R2-1, R2-2, R2-3) and R1-7
are resolved in the committed code, that each signed commit's tree equals its recorded tested tree,
and a search for problems introduced by the round-2 restructuring.

* qtbase `wip/cadisplaylink-gerrit` (worktree `qt5-series/qtbase`): G1 `33df309acc2`, G2
  `0bb7668b5f5`, G3 `e540b6b2c69`, G4 `4ecd0f4a096`, G5a `d6efb26498f`, G5b `bfdd5bad25a`, G5c
  `eaeb583f860`, G6 `fc439691c5e`, G7 `09ff153f888`.
* qtdeclarative `wip/cadisplaylink-gerrit` (worktree `qt5-series/qtdeclarative`): D1 `7c4be21eb2`,
  D2 `d8bc4071be`.
* wip heads: qtbase `fdfec4c10cf`, qtdeclarative `62d1e64eeb`.

`file:line` references are at the series heads (identical to the wip heads).

## Summary

The series is ready. Everything I checked in round 2 at the wip heads is now committed byte for
byte, split into commits that each stand on their own, and every round-2 finding is resolved in the
committed code:

* **The commits are what was tested.** All 11 signed commit trees equal the trees recorded in
  `/tmp/r2/series-trees.txt` and `/tmp/r2/decl-trees.txt` exactly. Both series heads are
  byte-identical to the wip heads, excluding `wip-cadisplaylink/` (`git diff` reports 0 differing
  files in each repo). So round 2's APPROVE of the wip-head code carries over unchanged.
* **Each commit is self-contained.** The chain is linear from the documented bases (qtbase
  `25d8223e59f`, qtdeclarative `ec2f2fdea8`), no merges, all signed (good signature,
  `a_liot@apple.com`). No commit references API that a later commit introduces: G1 uses no new API,
  G2 carries the private `updateRequestInterval` and the whole CADisplayLink/watchdog/stall logic
  with no `QAppleFrameRate*` reference, G5a is platform-independent, G5b (iOS) uses only G5a/G4/G2
  symbols, G5c wires cocoa to the G5a helper. Build logs (`/tmp/r2/series-logs/`) show each built
  state ending in success with 0 `error:`/`FAILED`.
* **Messages and docs are true at each commit.** The committed messages equal `/tmp/r2/msg/*.txt`
  plus the Gerrit `Change-Id` trailer, all body lines ≤ 72 columns, no WIP/round/reviewer/plan
  references anywhere. The property doc is split so that G4 states only the generic contract, G5c
  adds the macOS/iOS exact-rate and Qt Quick paragraphs, and G6 adds the Widgets paragraph — with
  no false claim at any stage (R2-2).
* **R2-1, R2-2, R2-3 resolved; R1-7 met.** See below.

I found no new problems. `tst_qappleframerate` on the committed final state: 151 passed, 0 failed.

Two items remain tracked as accepted deferrals, unchanged from round 2, both documented and neither
a code defect in the series: R1-1's ProMotion CVDisplayLink A/B (a pre-push condition, the panel
still isn't connected) and R1-10's qtmultimedia CVDisplayLink fallback (a follow-up outside the PR).

## What I verified

* **Tree equality (task 3).** For every commit, `git rev-parse <commit>^{tree}` equals the recorded
  tree:

  | Commit | Tree = recorded | Commit | Tree = recorded |
  |---|---|---|---|
  | G1 `33df309acc2` | `5ace0538…` ✓ | G5b `bfdd5bad25a` | `e6bd36c4…` ✓ |
  | G2 `0bb7668b5f5` | `17a18422…` ✓ | G5c `eaeb583f860` | `9157f9d2…` ✓ |
  | G3 `e540b6b2c69` | `68707163…` ✓ | G6 `fc439691c5e` | `e9aedc43…` ✓ |
  | G4 `4ecd0f4a096` | `0628c4ce…` ✓ | G7 `09ff153f888` | `b190b7b8…` ✓ |
  | G5a `d6efb26498f` | `8a20e6be…` ✓ | D1 `7c4be21eb2` | `36022fb8…` ✓ |
  | | | D2 `d8bc4071be` | `bbbccac4…` ✓ |

* **Series = wip head.** `git diff fdfec4c10cf 09ff153f888 -- . ':(exclude)wip-cadisplaylink/*'`:
  0 files. `git diff 62d1e64eeb d8bc4071be`: 0 files.
* **Parent chain / signatures.** qtbase G1's parent is `25d8223e59f`; qtdeclarative D1's parent is
  `ec2f2fdea8`; each commit has exactly one parent; all 11 show `G` (good signature).
* **Messages.** `diff` of each committed message against `/tmp/r2/msg/*.txt` is only the added
  `Change-Id` trailer. No line > 72 columns. `grep` for WIP/round-N/reviewer/R1-/R2-/qt5-series in
  the whole `25d8223e59f..09ff153f888` and `ec2f2fdea8..d8bc4071be` message ranges: none.
* **Build logs.** G1–G7 (minus G5b, iOS only) each end in `Built target …`, 0 errors.
* **Final-state test.** Rebuilt `tst_qappleframerate` in `qt5-build-cadisplaylink` at the wip head
  (`fdfec4c10cf`): **151 passed, 0 failed, 0 skipped, 13 ms** — the deterministic delivery/pacing
  model on the committed code.
* **License headers.** New sources (`qappleframerate.{cpp,_p.h}`):
  `LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only`. New tests
  (`tst_qappleframerate.cpp`, `tests/manual/displaylink/main.cpp`):
  `LicenseRef-Qt-Commercial OR GPL-3.0-only`, as required.
* **Net-diff scope.** `25d8223e59f..09ff153f888` (excluding `wip-cadisplaylink/`) touches only
  `examples/` (1), `src/` (25), `tests/` (10). No stray files.

## Per-commit assessment

| # | Commit | Builds at commit | Tests at commit | Message/docs true at commit |
|---|---|---|---|---|
| G1 | tst_QWindow delivery tests | QtGui, cocoa, tst_qwindow (log) | 7 fns pass **on the old CVDisplayLink plugin** (no-regression baseline) | Yes. `lastUpdateRequestInterval` is the test's own member, stays 0 at G1, so `unthrottledRates()` uses half-to-refresh bounds — no dependence on the nominal rate (R2-2). No new API referenced. |
| G2 | CADisplayLink switch | cocoa, tst_qwindow (log) | 9 pass; link reports its interval | Yes. Self-contained: adds private `updateRequestInterval`, full watchdog + R2-1 stall logic, no `QAppleFrameRate*` refs. Message states the pre-existing GCD freeze and the ≤3 s recovery. |
| G3 | CADisplayLink doc | QtGui (log) | doc/comments only (4 files) | Yes. macOS is CADisplayLink from G2; iOS already was. |
| G4 | `QWindow::preferredFrameRate` | QtGui, cocoa, tst_qwindow (log) | property + timer pacing | Yes. Doc has generic parts + timer-platform note + default-rate (all true at G4); message says "Pacing … on macOS and iOS follows separately". No macOS/iOS pacing claim (moved to G5c). |
| G5a | Shared frame-rate model | QtGui, tst_qappleframerate (log) | 151/151 | Yes. Platform-independent (only `src/gui/platform/darwin/…` + test). "The helper isn't used yet." |
| G5b | iOS pacing | not built on macOS (iOS only) | validated on the simulator at final state | Yes. Refs only G5a/G4/G2 symbols; iOS-plugin files only. |
| G5c | cocoa pacing + Apple doc | cocoa, tst_qwindow, tst_qappleframerate (log) | 43 passed, 1 skipped (two screens) | Yes. Replaces G2's loop with the G5a helper; adds the macOS/iOS exact-rate + Qt Quick doc paragraphs; frame-rate tests here (run on cocoa/ios, both pace by now). |
| G6 | Widgets pacing + Widgets doc | Widgets, tst_qwidgetrepaintmanager (log) | 18 passed, 1 focus failure (env) | Yes. Adds only the "For Qt Widgets" paragraph to the doc; `pacedUpdatesAfterRecreate` fails if pacing is lost; no `QT_WIDGETS_PACED_UPDATES`. |
| G7 | Manual test | standalone against series build | `--rate 30` → 30.0/s on 240 Hz | Yes. |
| D1 | Animation interval | qtdeclarative vs series qtbase | `stepsWithPreferredFrameRate`, `animatorDurationWithPreferredFrameRate` pass | Yes. Scene-graph + animation tests only, no QML doc / qquickwindow. |
| D2 | QML doc + tests | tst_qquickwindow | `preferredFrameRate*` pass | Yes. Doc + qquickwindow tests + scenegraph.qdoc. |

## Status of the round-2 and deferred findings

| ID | Round-2 status | Round-3 status | Evidence in the committed code |
|---|---|---|---|
| R1-7 | open (partial) | **Resolved** | Series committed, signed, linear from the bases; each commit builds (logs); trees equal the tested trees; README maps to the real hashes. |
| R2-1 | minor, open | **Fixed, accepted** | `qcocoascreen.mm:527-568` (`displayLinkWatchdogTimeout`): first timeout recreates the link (recoveries 0→1); a second consecutive timeout sets `m_displayLinkStalled=true`, `requestUpdate()` then returns false (`:402-406`), and `fallBackToTimerBasedUpdateRequests()` runs — bounding the freeze to ~T1+T2 (≈3 s). Reset at `deliverUpdateRequests()` `:464-465`. Sleep re-arm at max back-off `:545-547`. Present already at G2. Author's extended simulation (every link ignored 6 s) showed ~3 s freeze. `tst_qappleframerate` 151/151. |
| R2-2 | minor, open | **Fixed, accepted** | (1) G1 rate checks use `unthrottledRates()` half-to-refresh, `lastUpdateRequestInterval` stays 0 at G1; G2 adds the private `updateRequestInterval` (`qwindow_p.h`) and both the cocoa plugin and the test use it. (2) Doc split verified: G4 generic only; G5c adds the exact-rate/Qt Quick paragraphs and the "implemented on macOS and iOS" note; G6 adds only the Widgets paragraph — no double-add, no false claim. (3) G5 split into G5a (QtGui), G5b (iOS), G5c (cocoa); iOS precedes cocoa; frame-rate tests only from G5c. |
| R2-3 | nit, open | **Fixed, accepted** | Comment back above `AnimatingWidget` (`tst_qwidgetrepaintmanager.cpp:1106-1107`); `scenegraph.qdoc:446` links `\l{Window::preferredFrameRate}`; G2 message re-wrapped and notes the GCD-source freeze; G2 comment above `hasPendingDisplayLinkUpdateRequests()` describes it. |
| R1-1 | major, deferral accepted | **Deferral still accepted; pre-push condition outstanding** | Trigger sanitized, watchdog + stall recovery in place and disclosed (README "Known limitations", TESTING.md "Not run"). The CVDisplayLink A/B on the 120 Hz ProMotion panel is still not run (panel not connected) and is listed under README "Before sending to Gerrit". Must be done before the series is pushed, as agreed in round 2. |
| R1-10 | minor, deferral accepted | **Deferral still accepted** | `scenegraph.qdoc` fixed (D2); qtmultimedia's `avfdisplaylink.mm` CVDisplayLink fallback on macOS 14.x is a documented follow-up outside these repos. |

## New findings (round 3)

None. The restructuring introduced no new defects:

* **G5 split** (G5a/G5b/G5c): file boundaries are clean (QtGui / iOS / cocoa+doc+tests), ordering
  keeps every commit consistent (iOS pacing before the tst_qwindow frame-rate tests, which arrive
  in G5c and run on both Apple platforms).
* **G2 carrying `updateRequestInterval`**: the member is added in `qwindow_p.h` at G2, set during
  delivery and reset via a `QPointer` guard, read only by the test in qtbase; no released module
  reads it, so no behavior change for apps at G2.
* **Property doc split G4/G5c/G6**: each stage documents only what its commit implements.
* **R2-1 stall/timer-fallback**: traced through the two-timeout path; the freeze is bounded, the
  fallback timers stop on the first real callback, the link is invalidated (not leaked) on each
  recreation, and both flags reset in `deliverUpdateRequests()`. No unbounded freeze, no permanent
  double-delivery, no stuck-stalled state once the link recovers.

Observation, not a finding: at G4 the property doc's `\note` lists the timer platforms and the
platforms that ignore the preference, but not macOS/iOS, which at G4 also don't yet pace to the
preference (they pace from G5c). The commit message makes this explicit ("Pacing … on macOS and iOS
follows separately"), and adding "will be implemented" wording to G4 would be worse, so the chosen
split is correct. No action needed.

## Verdict

**APPROVE.** The committed Gerrit series is byte-identical to the round-2-approved wip heads, each
commit builds and its tests pass at its own state, every commit's tree equals the recorded tested
tree, and R2-1, R2-2, R2-3 and R1-7 are all resolved in the committed code. No blocker, major, minor
or nit is open against the code.

Two accepted deferrals remain tracked, both documented, neither a defect in the series:

* **R1-1 pre-push condition**: run the ProMotion 120 Hz CVDisplayLink-vs-CADisplayLink stall A/B
  and record it in TESTING.md before the series is pushed to Gerrit (panel not connected here).
* **R1-10 follow-up**: drop qtmultimedia's `@available(macOS 15.0)` CVDisplayLink fallback
  (outside these repos).

Counts (new this round): blocker 0, major 0, minor 0, nit 0.
Round-2 findings: R1-7, R2-1, R2-2, R2-3 all resolved.

Open (tracked deferrals, non-blocking):

* R1-1 major (deferred): ProMotion CVDisplayLink A/B not yet run — pre-push condition.
* R1-10 minor (deferred): qtmultimedia still uses CVDisplayLink on macOS 14.x — follow-up outside the PR.
