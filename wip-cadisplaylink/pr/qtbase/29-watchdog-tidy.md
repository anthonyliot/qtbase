# 29 cocoa: Tidy up the nested event loop watchdog

| | |
|---|---|
| Commit | `5c00de26f2b` (qtbase) |
| Files | `qcocoascreen{.h,.mm}` |
| Plan | Squash into 23 |

## What
Forward declare `QTimer` in `qcocoascreen.h` (the `std::unique_ptr<QTimer>` member only needs the
complete type where the destructor is, in the .mm), and give the watchdog's timeout connection
the timer as context object.
