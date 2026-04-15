import Foundation
import SwiftUI

struct TrackedTimeZone: Identifiable {
    let identifier: String
    let displayName: String

    var id: String { identifier }

    static let defaults: [TrackedTimeZone] = [
        TrackedTimeZone(identifier: "Europe/Rome"),
        TrackedTimeZone(identifier: "America/New_York"),
        TrackedTimeZone(identifier: "Asia/Tokyo"),
    ]

    init(identifier: String, displayName: String? = nil) {
        self.identifier = identifier
        self.displayName = displayName ?? Self.defaultDisplayName(for: identifier)
    }

    private static func defaultDisplayName(for identifier: String) -> String {
        identifier
            .split(separator: "/")
            .last
            .map { $0.replacingOccurrences(of: "_", with: " ") } ?? identifier
    }
}

@MainActor
final class TimeZoneStore: ObservableObject {
    @Published private(set) var zones: [TrackedTimeZone]
    @Published private(set) var visibleZones: Set<String>
    @Published private(set) var now = Date()

    private let defaults = UserDefaults.standard
    private let zonesKey = "trackedTimeZones"
    private let visibleZonesKey = "visibleMenuBarTimeZones"
    private var clockTask: Task<Void, Never>?

    init(zones: [TrackedTimeZone]) {
        let persisted = Self.loadZones(defaults: UserDefaults.standard, key: zonesKey)
        let resolvedZones = persisted.isEmpty ? zones : persisted
        let persistedVisible = Self.loadVisibleZones(defaults: UserDefaults.standard, key: visibleZonesKey)

        self.zones = resolvedZones
        self.visibleZones = persistedVisible.isEmpty
            ? Set(resolvedZones.prefix(2).map(\.identifier))
            : persistedVisible.intersection(Set(resolvedZones.map(\.identifier)))

        start()
    }

    var menuBarTitle: String {
        let parts = zones.filter { visibleZones.contains($0.identifier) }.map { zone in
            "\(shortName(for: zone)) \(timeText(for: zone.identifier))"
        }

        return parts.isEmpty ? "Zonebar" : parts.joined(separator: "  ")
    }

    func start() {
        guard clockTask == nil else {
            return
        }

        clockTask = Task {
            while !Task.isCancelled {
                now = Date()

                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
            }
        }
    }

    func updateZones(from input: String) {
        let parsed = Self.parseZones(from: input)
        guard !parsed.isEmpty else {
            return
        }

        zones = parsed

        let validZones = Set(parsed.map(\.identifier))
        visibleZones = visibleZones.intersection(validZones)
        if visibleZones.isEmpty {
            visibleZones = Set(parsed.prefix(2).map(\.identifier))
        }

        defaults.set(parsed.map(\.identifier), forKey: zonesKey)
        defaults.set(Array(visibleZones), forKey: visibleZonesKey)
    }

    func editableZonesText() -> String {
        zones.map(\.identifier).joined(separator: "\n")
    }

    func showsInMenuBar(_ identifier: String) -> Bool {
        visibleZones.contains(identifier)
    }

    func setMenuBarVisibility(for identifier: String, isVisible: Bool) {
        if isVisible {
            visibleZones.insert(identifier)
        } else {
            visibleZones.remove(identifier)
        }

        defaults.set(Array(visibleZones), forKey: visibleZonesKey)
    }

    func timeText(for identifier: String) -> String {
        guard let timeZone = TimeZone(identifier: identifier) else {
            return "--:--"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = timeZone
        return formatter.string(from: now)
    }

    func dateText(for identifier: String) -> String {
        guard let timeZone = TimeZone(identifier: identifier) else {
            return "Invalid timezone"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d MMM"
        formatter.timeZone = timeZone
        return formatter.string(from: now)
    }

    func offsetText(for identifier: String) -> String {
        guard let timeZone = TimeZone(identifier: identifier) else {
            return "--"
        }

        let seconds = timeZone.secondsFromGMT(for: now)
        let sign = seconds >= 0 ? "+" : "-"
        let absoluteSeconds = abs(seconds)
        let hours = absoluteSeconds / 3600
        let minutes = (absoluteSeconds % 3600) / 60

        if minutes == 0 {
            return "UTC\(sign)\(hours)"
        }

        return "UTC\(sign)\(hours):\(String(format: "%02d", minutes))"
    }

    private func shortName(for zone: TrackedTimeZone) -> String {
        let words = zone.displayName.split(separator: " ")

        guard words.count > 1 else {
            return zone.displayName
        }

        return words
            .map { String($0.prefix(1)) }
            .joined()
            .uppercased()
    }

    private static func loadZones(defaults: UserDefaults, key: String) -> [TrackedTimeZone] {
        guard let stored = defaults.stringArray(forKey: key) else {
            return []
        }

        return stored.map { TrackedTimeZone(identifier: $0) }
    }

    private static func loadVisibleZones(defaults: UserDefaults, key: String) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    private static func parseZones(from input: String) -> [TrackedTimeZone] {
        let tokens = input
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        var zones: [TrackedTimeZone] = []

        for token in tokens where TimeZone(identifier: token) != nil && seen.insert(token).inserted {
            zones.append(TrackedTimeZone(identifier: token))
        }

        return zones
    }
}
