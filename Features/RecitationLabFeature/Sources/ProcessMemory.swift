//
//  ProcessMemory.swift
//
//
//  Created by Claude Code on 2026-11-27.
//

import Darwin

/// The app's memory footprint as the system counts it against its limit (`phys_footprint`, the
/// number Xcode's memory gauge shows), for the developer screen's measurements.
enum ProcessMemory {
    static func footprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }
}
