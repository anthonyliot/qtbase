// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

// Usage: qt-rusage <pid> <seconds>  -- per-second CPU %, interrupt/idle wakeups, billed energy (mW) of a process
import Darwin
import Foundation
let pid = Int32(CommandLine.arguments[1])!, secs = Int(CommandLine.arguments[2])!
var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
func sample() -> rusage_info_v4? {
    var info = rusage_info_v4()
    let r = withUnsafeMutablePointer(to: &info) { p in
        p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
    }
    return r == 0 ? info : nil
}
guard var prev = sample() else { print("cannot sample pid \(pid)"); exit(1) }
var prevT = mach_absolute_time()
for i in 1...secs {
    sleep(1)
    guard let cur = sample() else { break }
    let now = mach_absolute_time()
    let wall = Double(now - prevT) * Double(tb.numer) / Double(tb.denom) / 1e9
    let cpuNs = Double((cur.ri_user_time + cur.ri_system_time) - (prev.ri_user_time + prev.ri_system_time)) * Double(tb.numer) / Double(tb.denom)
    let intw = Double(cur.ri_interrupt_wkups - prev.ri_interrupt_wkups) / wall
    let idlew = Double(cur.ri_pkg_idle_wkups - prev.ri_pkg_idle_wkups) / wall
    let mW = Double(cur.ri_billed_energy - prev.ri_billed_energy) / wall / 1e6
    print(String(format: "s=%d cpu=%.1f intw=%.0f idlew=%.0f energy_mW=%.1f", i, cpuNs / 1e9 / wall * 100, intw, idlew, mW))
    fflush(stdout)
    prev = cur; prevT = now
}
