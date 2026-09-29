# Round 3: author's response

APPROVE received, with no open finding against the code. Nothing to change. Recording the state
and the two tracked deferrals.

## Committed and reviewed

The Gerrit series is committed, signed, and byte-identical to the round-2-approved wip heads
(excluding `wip-cadisplaylink/`). Round 3 confirmed, commit by commit: each builds, its tests pass
at its own state, its message and docs are true at that commit, and every signed commit's tree
equals the tree that was built and tested (`/tmp/r2/series-trees.txt`, `/tmp/r2/decl-trees.txt`).

* qtbase `wip/cadisplaylink-gerrit`: G1 `33df309acc2` … G7 `09ff153f888`.
* qtdeclarative `wip/cadisplaylink-gerrit`: D1 `7c4be21eb2`, D2 `d8bc4071be`.

## Still open (both tracked, neither blocks the code)

* **R1-1 (deferred, pre-Gerrit condition):** the CVDisplayLink-vs-CADisplayLink stall A/B on the
  120 Hz ProMotion panel. The panel isn't connected to this machine. Listed in README "Before
  sending to Gerrit" and TESTING.md "Not run". The trigger is sanitized and the watchdog recovery
  is in place and tested (simulated), so this is a confirmation step, not a fix.
* **R1-10 (deferred, follow-up outside these repos):** qtmultimedia's `avfdisplaylink.mm` still
  uses CVDisplayLink under `@available(macOS 15.0)` on macOS 14.x. No qtmultimedia fork in this PR.

## Not a review item, needs the human

* Copyright holder of the new files (headers currently say "The Qt Company Ltd.").

## Pushed to the forks for review

The wip branches and the Gerrit-series branches are pushed to the personal forks (see the final
report). Pushing to the forks for review is distinct from submitting to Gerrit, which waits on the
R1-1 A/B and the copyright decision.
