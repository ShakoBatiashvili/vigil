/// Arithmetic on the raw numbers the battery reports.
public enum BatteryMath {
    /// The IORegistry stores a signed amperage (negative = discharging) as its
    /// unsigned 64-bit two's complement.
    public static func signedAmperage(raw: UInt64) -> Int64 {
        Int64(bitPattern: raw)
    }

    /// Instantaneous power in watts, as a magnitude. mA x mV = uW.
    public static func watts(amperageMilliamps: Int64, voltageMillivolts: Int) -> Double {
        guard voltageMillivolts > 0 else { return 0 }
        return abs(Double(amperageMilliamps)) * Double(voltageMillivolts) / 1_000_000
    }
}
