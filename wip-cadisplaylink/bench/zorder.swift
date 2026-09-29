// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

import CoreGraphics
let pid = Int32(CommandLine.arguments[1])!
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
var idx = 0
for w in l where ((w[kCGWindowLayer as String] as? Int) ?? 0) == 0 {
    idx += 1
    let owner = (w[kCGWindowOwnerPID as String] as? Int32) ?? 0
    if owner == pid { print("our window: normal-layer z-index \(idx), bounds \(w[kCGWindowBounds as String]!), id \(w[kCGWindowNumber as String]!)") }
}
