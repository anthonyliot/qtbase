# Round 14: author's response (qtmultimedia series)

Verdict received: APPROVE (nit 2). Both nits fixed, in the documents and `M5.txt` only; no tree
changed (S5 `d7b28d110a2f`, S6 `395ad6fdce8e`).

| ID | Response |
|---|---|
| R14-1 nit | **Fixed.** README:224 names Display and Core Animation Commits. `analyze.py` has its commits/s column back (121.5 to 122.1 in the `l3` AVFoundation runs), and TESTING names it as the source. FFmpeg's default wait is "3 to 6 ms" in `M5.txt`, README and the M5 document, and TESTING gives `c5` run 2's 3 ms. The slip's cost is "measured on the render side only, in `c4`'s Qt log after its recording, never on screen". TESTING says "48 Hz for the recording's first 3.8 s" and "over the runs". |
| R14-2 nit | **Fixed.** README says "review rounds 4 to 14". The M5 document's Tests section says the tests were written on the G95SC, and how they run on the ProMotion panel. TESTING's "Suites on the final state" and "Series states" say that the current S5 and S6 have the same library code as round 11's, which is why only M5's suites ran again. The run-groups table has `c4-*`. `qtbase-docs.txt` says rounds 13 and 14. |
