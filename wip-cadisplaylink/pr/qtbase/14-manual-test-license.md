# 14 displaylink manual test: Use the license required for tests

| | |
|---|---|
| Commit | `0adee5889c3` (qtbase) |
| Files | `tests/manual/displaylink/main.cpp` |
| Plan | Squash into 08 |

## What
`SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only` instead of BSD-3-Clause.

## Why
Qt's license check requires that for sources under `tests/`; BSD is only for examples, snippets
and CMake files.
