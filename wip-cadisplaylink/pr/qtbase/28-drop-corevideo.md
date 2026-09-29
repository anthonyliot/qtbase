# 28 cocoa: Don't link CoreVideo anymore

| | |
|---|---|
| Commit | `7a6a8974c1a` (qtbase) |
| Files | `src/plugins/platforms/cocoa/CMakeLists.txt`, `qcocoa_plugin_pch.h` |
| Plan | Squash into 03 |

## What
Drop `${FWCoreVideo}` and the `<CoreVideo/CoreVideo.h>` precompiled header include.

## Why
Found in the fresh review of the full diff: no CoreVideo symbol is used in the plugin since 03
(`grep -E '\bCV[A-Z]'` finds nothing).

## Verify
The plugin builds, and `otool -L libqcocoa*.dylib` doesn't list CoreVideo.
