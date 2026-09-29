# G7 Add a manual test for update request pacing and frame rates

| | |
|---|---|
| Files | `tests/manual/CMakeLists.txt`, `tests/manual/displaylink/{CMakeLists.txt,main.cpp}` |
| From | old 08, 11, 14, 26 |

## Verified
At G7: built as a standalone test project against the series build (the series build has
printsupport off, which another manual test needs, so manual tests are off there); `--rate 30` gives
30.0 update requests per second on the 240 Hz display.
