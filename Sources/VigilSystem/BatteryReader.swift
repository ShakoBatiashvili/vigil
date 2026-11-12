import Foundation
import IOKit
import IOKit.ps
import VigilCore

public struct BatterySnapshot: Equatable, Sendable {
    /// `nil` on a Mac without a battery.
    public var percent: Int?
    public var onAC: Bool
    public var isCharging: Bool
    /// Instantaneous power through the battery, in watts (magnitude). While on
    /// battery this is the whole machine's draw; on AC it's the charge rate.
    public var watts: Double?
    public var timeRemainingMinutes: Int?
    public var cycleCount: Int?

    public init(percent: Int?, onAC: Bool, isCharging: Bool, watts: Double?,
                timeRemainingMinutes: Int?, cycleCount: Int?) {
        self.percent = percent
        self.onAC = onAC
        self.isCharging = isCharging
        self.watts = watts
        self.timeRemainingMinutes = timeRemainingMinutes
        self.cycleCount = cycleCount
    }

    public var reading: BatteryReading { BatteryReading(percent: percent, onAC: onAC) }
}

/// Battery facts from public IOKit APIs; no privileges required.
public enum BatteryReader {
    public static func read() -> BatterySnapshot {
        var snapshot = BatterySnapshot(percent: nil, onAC: true, isCharging: false,
                                       watts: nil, timeRemainingMinutes: nil, cycleCount: nil)

        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() {
            if let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? {
                snapshot.onAC = (providing == kIOPMACPowerKey)
            }
            let sources = (IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as [CFTypeRef]?) ?? []
            for source in sources {
                guard let description = IOPSGetPowerSourceDescription(info, source)?
                        .takeUnretainedValue() as? [String: Any],
                      (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
                else { continue }
                if let current = description[kIOPSCurrentCapacityKey] as? Int,
                   let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 {
                    snapshot.percent = min(100, max(0, current * 100 / maximum))
                }
                snapshot.isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
                break
            }
        }

        let estimate = IOPSGetTimeRemainingEstimate()
        if estimate >= 0 { snapshot.timeRemainingMinutes = Int(estimate / 60) }

        if let properties = smartBatteryProperties() {
            if let amperage = properties["InstantAmperage"] as? NSNumber ?? properties["Amperage"] as? NSNumber,
               let voltage = properties["Voltage"] as? NSNumber {
                snapshot.watts = BatteryMath.watts(
                    amperageMilliamps: BatteryMath.signedAmperage(raw: amperage.uint64Value),
                    voltageMillivolts: voltage.intValue
                )
            }
            snapshot.cycleCount = (properties["CycleCount"] as? NSNumber)?.intValue
        }
        return snapshot
    }

    private static func smartBatteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else {
            return nil
        }
        return properties?.takeRetainedValue() as? [String: Any]
    }
}
