import Foundation

/// One process's energy impact plus the facts needed to name it.
public struct ProcessEnergy: Equatable, Sendable {
    public var pid: Int32
    public var power: Double
    public var path: String?
    public var fallbackName: String

    public init(pid: Int32, power: Double, path: String?, fallbackName: String) {
        self.pid = pid
        self.power = power
        self.path = path
        self.fallbackName = fallbackName
    }
}

/// One row of the "what drains the battery" list: an app (with all its helper
/// processes rolled up) or a plain executable.
public struct AppDrain: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// The outermost `.app` directory, used to fetch the icon. `nil` for daemons.
    public var bundlePath: String?
    public var power: Double
    /// Fraction (0...1) of the total energy impact of ALL processes.
    public var share: Double
    public var processCount: Int
    public var isOther: Bool

    public init(id: String, name: String, bundlePath: String?, power: Double, share: Double,
                processCount: Int, isOther: Bool) {
        self.id = id
        self.name = name
        self.bundlePath = bundlePath
        self.power = power
        self.share = share
        self.processCount = processCount
        self.isOther = isOther
    }
}

public enum DrainModel {
    /// "Google Chrome" for any path inside `Google Chrome.app`, helpers included.
    public static func appName(fromPath path: String) -> String? {
        guard let (_, component) = firstAppComponent(in: path) else { return nil }
        return String(component.dropLast(4))
    }

    public static func bundlePath(fromPath path: String) -> String? {
        guard let (index, _) = firstAppComponent(in: path) else { return nil }
        return path.split(separator: "/", omittingEmptySubsequences: false)[...index].joined(separator: "/")
    }

    /// True for names made only of digits and dots, like "2.1.322".
    public static func isVersionLike(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
    }

    private static func firstAppComponent(in path: String) -> (Int, Substring)? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") && $0.count > 4 }) else { return nil }
        return (index, components[index])
    }

    /// Groups processes by app, sorts by energy, keeps the `top` biggest and folds
    /// the rest into one "Other" row. Idle processes are ignored entirely.
    public static func group(_ rows: [ProcessEnergy], top: Int) -> [AppDrain] {
        struct Bucket { var id: String; var name: String; var bundlePath: String?; var power = 0.0; var count = 0 }
        var buckets: [String: Bucket] = [:]
        var total = 0.0

        for row in rows where row.power.isFinite && row.power > 0 {
            var bucket: Bucket
            if let path = row.path, let app = appName(fromPath: path), let bundle = bundlePath(fromPath: path) {
                bucket = buckets[bundle] ?? Bucket(id: bundle, name: app, bundlePath: bundle)
            } else if let path = row.path, !path.isEmpty {
                let base = (path as NSString).lastPathComponent
                // "…/claude/versions/2.1.322" is named after its version; the process name says what it is.
                let name = (isVersionLike(base) && !row.fallbackName.isEmpty) ? row.fallbackName : base
                bucket = buckets[path] ?? Bucket(id: path, name: name, bundlePath: nil)
            } else {
                let key = "name:" + row.fallbackName
                bucket = buckets[key] ?? Bucket(id: key, name: row.fallbackName, bundlePath: nil)
            }
            bucket.power += row.power
            bucket.count += 1
            buckets[bucket.id] = bucket
            total += row.power
        }
        guard total > 0 else { return [] }

        let sorted = buckets.values.sorted {
            $0.power != $1.power ? $0.power > $1.power : $0.name < $1.name
        }
        let limit = max(top, 0)
        var result = sorted.prefix(limit).map {
            AppDrain(id: $0.id, name: $0.name, bundlePath: $0.bundlePath, power: $0.power,
                     share: $0.power / total, processCount: $0.count, isOther: false)
        }
        let rest = sorted.dropFirst(limit)
        if !rest.isEmpty {
            let power = rest.reduce(0) { $0 + $1.power }
            result.append(AppDrain(id: "other", name: "Other", bundlePath: nil, power: power,
                                   share: power / total, processCount: rest.reduce(0) { $0 + $1.count },
                                   isOther: true))
        }
        return result
    }
}
