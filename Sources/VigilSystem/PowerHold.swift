import Foundation
import IOKit.pwr_mgt
import VigilCore

/// Holds the Mac awake with IOKit power assertions (the same mechanism as
/// `caffeinate`). The kernel drops a process's assertions when it exits, so a
/// crash can never leave the Mac stuck awake.
///
/// Not thread-safe: drive it from one actor (the app's main actor / the CLI's main thread).
public final class PowerHold {
    private var ids: [HolderKind: IOPMAssertionID] = [:]
    private var reasons: [HolderKind: String] = [:]

    public init() {}
    deinit { releaseAll() }

    public var heldKinds: Set<HolderKind> { Set(ids.keys) }

    /// Reconciles the live assertions to exactly what is requested. Idempotent.
    public func apply(system: Bool, display: Bool, reason: String) {
        reconcile(.system, wanted: system, reason: reason)
        reconcile(.display, wanted: display, reason: reason)
    }

    public func releaseAll() {
        apply(system: false, display: false, reason: "")
    }

    private func reconcile(_ kind: HolderKind, wanted: Bool, reason: String) {
        if !wanted {
            if let id = ids.removeValue(forKey: kind) { IOPMAssertionRelease(id) }
            reasons[kind] = nil
            return
        }
        if let id = ids[kind] {
            if reasons[kind] != reason {
                IOPMAssertionSetProperty(id, kIOPMAssertionNameKey as CFString, reason as CFString)
                reasons[kind] = reason
            }
            return
        }
        var id = IOPMAssertionID(0)
        let type = (kind == .system ? kIOPMAssertPreventUserIdleSystemSleep : kIOPMAssertPreventUserIdleDisplaySleep)
        let result = IOPMAssertionCreateWithName(
            type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &id
        )
        if result == kIOReturnSuccess {
            ids[kind] = id
            reasons[kind] = reason
        }
    }
}
