/// Decides when keep-awake must be released to protect the battery.
///
/// Pure and latched: once tripped on battery it stays tripped until the power
/// adapter is connected, so a jittery gauge can never quietly re-engage the hold.
public enum BatteryGuard {
    public static func isTripped(
        percent: Int?,
        onAC: Bool,
        threshold: Int,
        wasTripped: Bool
    ) -> Bool {
        if onAC { return false }          // plugged in: nothing to protect, latch clears
        if wasTripped { return true }     // still on battery: stay released
        guard let percent else { return false }   // no battery (desktop): guard is inert
        return percent < threshold
    }
}
