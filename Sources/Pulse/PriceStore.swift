import AppKit
import Foundation
import OSLog
import SwiftUI
import Yams

private let hyperliquidLogger = Logger(subsystem: "crypto-tracker", category: "hyperliquid")

enum MarketProvider: String, CaseIterable, Sendable {
    case binance
    case hyperliquid
    case time
    case spacer
    case label

    var displayName: String {
        switch self {
        case .binance:
            return "Binance"
        case .hyperliquid:
            return "Hyperliquid"
        case .time:
            return "Time"
        case .spacer:
            return "Spacer"
        case .label:
            return "Label"
        }
    }

    var shortLabel: String {
        switch self {
        case .binance:
            return "BN"
        case .hyperliquid:
            return "HL"
        case .time, .spacer, .label:
            return ""
        }
    }

    func tradeURL(for symbol: String) -> URL? {
        switch self {
        case .binance:
            return URL(string: "https://www.binance.com/en/trade/\(symbol)")
        case .hyperliquid:
            return URL(string: "https://app.hyperliquid.xyz/trade/\(symbol)")
        case .time, .spacer, .label:
            return nil
        }
    }

    var symbolPlaceholder: String {
        switch self {
        case .binance:
            return "BTCUSDT"
        case .hyperliquid:
            return "BTC or xyz:CL"
        case .time:
            return "America/New_York"
        case .spacer:
            return ""
        case .label:
            return "DeFi"
        }
    }
}

struct TrackedSymbol: Identifiable, Sendable {
    let provider: MarketProvider
    let symbol: String
    let displayName: String

    var id: String { storageValue }

    var storageValue: String {
        "\(provider.rawValue):\(symbol)"
    }

    static let defaults: [TrackedSymbol] = [
        TrackedSymbol(symbol: "BTCUSDT", displayName: "BTC"),
        TrackedSymbol(symbol: "ETHUSDT", displayName: "ETH"),
        TrackedSymbol(symbol: "SOLUSDT", displayName: "SOL"),
    ]

    init(provider: MarketProvider = .binance, symbol: String, displayName: String? = nil) {
        self.provider = provider

        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSymbol = TrackedSymbol.normalizedSymbol(trimmedSymbol, for: provider)
        self.symbol = normalizedSymbol
        self.displayName = displayName ?? TrackedSymbol.defaultDisplayName(for: provider, symbol: normalizedSymbol)
    }

    init?(token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.count == 2 {
            let providerToken = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let symbolToken = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard let provider = MarketProvider(rawValue: providerToken), !symbolToken.isEmpty else {
                return nil
            }

            if provider == .time && TimeZone(identifier: symbolToken) == nil {
                return nil
            }

            self.init(provider: provider, symbol: symbolToken)
            return
        }

        self.init(symbol: trimmed)
    }

    private static func normalizedSymbol(_ symbol: String, for provider: MarketProvider) -> String {
        switch provider {
        case .binance:
            return symbol.uppercased()
        case .hyperliquid, .time, .spacer, .label:
            return symbol
        }
    }

    private static func defaultDisplayName(for provider: MarketProvider, symbol: String) -> String {
        switch provider {
        case .binance:
            if symbol.hasSuffix("USDT") {
                return String(symbol.dropLast(4))
            }
            return symbol
        case .hyperliquid:
            return symbol
        case .time:
            let city = symbol.split(separator: "/").last
                .map { $0.replacingOccurrences(of: "_", with: " ") } ?? symbol
            let words = city.split(separator: " ")
            guard words.count > 1 else { return city }
            return words.map { String($0.prefix(1)) }.joined().uppercased()
        case .spacer:
            return ""
        case .label:
            return symbol
        }
    }
}

struct PriceSnapshot: Sendable {
    let symbol: String
    let lastPrice: Double
    let changePercent: Double

    var formattedPrice: String {
        PriceFormatter.string(from: lastPrice) ?? "--"
    }

    var formattedPercent: String {
        let prefix = changePercent >= 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.2f", changePercent))%"
    }

    var changeColor: Color {
        if changePercent > 0 {
            return .green
        }

        if changePercent < 0 {
            return .red
        }

        return .secondary
    }
}

private enum BinanceMarket: String, Sendable {
    case spot
    case futures

    var tickerProbeURL: URL {
        switch self {
        case .spot:
            return URL(string: "https://api.binance.com/api/v3/ticker/24hr")!
        case .futures:
            return URL(string: "https://fapi.binance.com/fapi/v1/ticker/24hr")!
        }
    }

    var websocketBaseURL: String {
        switch self {
        case .spot:
            return "wss://stream.binance.com:9443/stream?streams="
        case .futures:
            return "wss://fstream.binance.com/stream?streams="
        }
    }
}

private struct ResolvedBinanceSymbol: Sendable {
    let tracked: TrackedSymbol
    let market: BinanceMarket
}

private struct HyperliquidMarketSnapshot: Sendable {
    let availableCoins: Set<String>
    let midPrices: [String: Double]
    let prevDayPrices: [String: Double]
    /// Maps spot @N universe keys to their xyz:NAME aliases (e.g. "@264" → "xyz:TSLA")
    let spotAliases: [String: String]
}

private struct ConfigItem: Codable {
    var type: String
    var value: String?
    var label: String?
    var visible: Bool?
}

private struct PulseConfig: Codable {
    var items: [ConfigItem] = []
    var divider: String = ""
    var gap: Int = 3
    var separatorWidth: Int = 6

    init(items: [ConfigItem] = [], divider: String = "", gap: Int = 3, separatorWidth: Int = 6) {
        self.items = items
        self.divider = divider
        self.gap = gap
        self.separatorWidth = separatorWidth
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([ConfigItem].self, forKey: .items)) ?? []
        divider = (try? c.decodeIfPresent(String.self, forKey: .divider)) ?? ""
        gap = (try? c.decodeIfPresent(Int.self, forKey: .gap)) ?? 3
        separatorWidth = (try? c.decodeIfPresent(Int.self, forKey: .separatorWidth)) ?? 6
    }
}

@MainActor
final class PriceStore: ObservableObject {
    @Published private(set) var prices: [String: PriceSnapshot] = [:]
    @Published private(set) var connectionStatus = "Connecting..."
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var symbols: [TrackedSymbol]
    @Published private(set) var visibleSymbols: Set<String>

    @Published private(set) var customNames: [String: String] = [:]
    @Published private(set) var menuBarDivider: String = ""
    @Published private(set) var menuBarGap: Int = 3
    @Published private(set) var menuBarSeparatorWidth: Int = 6

    private var streamTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var resolvedBinanceMarkets: [String: BinanceMarket] = [:]
    private var xyzPerpPrevDayPrices: [String: Double] = [:]
    @Published private(set) var now = Date()

    private static let configURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".config/pulse/config.yaml")

    private static func loadConfig() -> PulseConfig {
        guard let yaml = try? String(contentsOf: configURL, encoding: .utf8) else { return PulseConfig() }
        return (try? YAMLDecoder().decode(PulseConfig.self, from: yaml)) ?? PulseConfig()
    }

    private func saveConfig() {
        let items: [ConfigItem] = symbols.map { symbol in
            ConfigItem(
                type: symbol.provider.rawValue,
                value: symbol.provider == .spacer ? nil : symbol.symbol,
                label: customNames[symbol.id],
                visible: symbol.provider == .spacer || symbol.provider == .label
                    ? nil
                    : visibleSymbols.contains(symbol.id)
            )
        }
        let config = PulseConfig(
            items: items,
            divider: menuBarDivider,
            gap: menuBarGap,
            separatorWidth: menuBarSeparatorWidth
        )
        do {
            let dir = Self.configURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let yaml = try YAMLEncoder().encode(config)
            try yaml.write(to: Self.configURL, atomically: true, encoding: .utf8)
        } catch {
            // config directory or write failed — settings won't persist this session
        }
    }

    private static func unpackConfig(_ config: PulseConfig) -> (
        symbols: [TrackedSymbol],
        visibleSymbols: Set<String>,
        customNames: [String: String]
    ) {
        var symbols: [TrackedSymbol] = []
        var visibleSymbols: Set<String> = []
        var customNames: [String: String] = [:]

        for item in config.items {
            let token = item.type == "spacer"
                ? "spacer:\(UUID().uuidString)"
                : "\(item.type):\(item.value ?? "")"
            guard let symbol = TrackedSymbol(token: token) else { continue }
            symbols.append(symbol)
            if item.visible == true { visibleSymbols.insert(symbol.id) }
            if let label = item.label, !label.isEmpty { customNames[symbol.id] = label }
        }

        return (symbols, visibleSymbols, customNames)
    }

    init(symbols defaultSymbols: [TrackedSymbol]) {
        let config = Self.loadConfig()
        let unpacked = Self.unpackConfig(config)

        let resolvedSymbols = unpacked.symbols.isEmpty ? defaultSymbols : unpacked.symbols
        self.symbols = resolvedSymbols
        self.visibleSymbols = unpacked.visibleSymbols.isEmpty
            ? Set(resolvedSymbols.prefix(2).map { $0.id })
            : unpacked.visibleSymbols.intersection(Set(resolvedSymbols.map { $0.id }))
        self.customNames = unpacked.customNames
        self.menuBarDivider = config.divider
        self.menuBarGap = config.gap
        self.menuBarSeparatorWidth = config.separatorWidth

        start()
    }

    func displayName(for symbol: TrackedSymbol) -> String {
        customNames[symbol.id] ?? symbol.displayName
    }

    func setMenuBarDivider(_ separator: String) {
        menuBarDivider = separator
        saveConfig()
    }

    func setMenuBarGap(_ padding: Int) {
        menuBarGap = max(0, padding)
        saveConfig()
    }

    func setMenuBarSeparatorWidth(_ width: Int) {
        menuBarSeparatorWidth = max(0, width)
        saveConfig()
    }

    private var menuBarJoinString: String {
        let pad = String(repeating: " ", count: menuBarGap)
        return menuBarDivider.isEmpty ? pad : pad + menuBarDivider + pad
    }

    func renameSymbol(id: String, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            customNames.removeValue(forKey: id)
        } else {
            customNames[id] = trimmed
        }
        saveConfig()
    }

    var menuBarTitle: String {
        let visible = symbols.filter { $0.provider == .spacer || ($0.provider != .label && visibleSymbols.contains($0.id)) }
        if visible.isEmpty { return "Pulse" }

        var result = ""
        var pendingSpacer = false

        for symbol in visible {
            if symbol.provider == .spacer {
                pendingSpacer = true
                continue
            }

            let name = displayName(for: symbol)
            let text: String
            if symbol.provider == .time {
                text = "\(name) \(timeText(for: symbol.symbol))"
            } else {
                text = "\(name) \(prices[symbol.id]?.formattedPrice ?? "--")"
            }

            if result.isEmpty {
                result = text
            } else if pendingSpacer {
                result += String(repeating: " ", count: menuBarSeparatorWidth) + text
            } else {
                result += menuBarJoinString + text
            }
            pendingSpacer = false
        }

        return result.isEmpty ? "Pulse" : result
    }

    func timeText(for identifier: String) -> String {
        guard let timeZone = TimeZone(identifier: identifier) else { return "--:--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = timeZone
        return formatter.string(from: now)
    }

    func timeDifferenceText(for identifier: String) -> String? {
        guard let zone = TimeZone(identifier: identifier) else { return nil }
        let localOffset = TimeZone.current.secondsFromGMT(for: now)
        let zoneOffset = zone.secondsFromGMT(for: now)
        let diffHours = (zoneOffset - localOffset) / 3600
        if diffHours == 0 { return nil }
        return diffHours > 0 ? "+\(diffHours)h" : "\(diffHours)h"
    }

    func start() {
        if clockTask == nil {
            clockTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    now = Date()
                }
            }
        }

        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.restart() }
            }
        }

        guard streamTask == nil else {
            return
        }

        streamTask = Task {
            await runConnectionLoop()
        }
    }

    func restart() {
        streamTask?.cancel()
        streamTask = nil
        connectionStatus = "Reconnecting..."
        start()
    }

    func updateSymbols(from input: String) {
        let parsed = Self.parseSymbols(from: input)
        guard !parsed.isEmpty else {
            return
        }

        symbols = parsed
        let validSymbolIDs = Set(parsed.map(\.id))
        prices = prices.filter { validSymbolIDs.contains($0.key) }
        visibleSymbols = visibleSymbols.intersection(validSymbolIDs)
        if visibleSymbols.isEmpty {
            visibleSymbols = Set(parsed.prefix(2).map(\.id))
        }
        resolvedBinanceMarkets = resolvedBinanceMarkets.filter { validSymbolIDs.contains($0.key) }
        lastUpdated = nil
        saveConfig()
        restart()
    }

    func moveSymbol(from source: IndexSet, to destination: Int) {
        symbols.move(fromOffsets: source, toOffset: destination)
        saveConfig()
    }

    func addSpacer() {
        let symbol = TrackedSymbol(provider: .spacer, symbol: UUID().uuidString)
        symbols.append(symbol)
        visibleSymbols.insert(symbol.id)
        saveConfig()
    }

    func addLabel(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let symbol = TrackedSymbol(provider: .label, symbol: trimmed)
        guard !symbols.contains(where: { $0.id == symbol.id }) else { return }
        symbols.append(symbol)
        saveConfig()
    }

    /// Returns true if the symbol was added, false if the token is invalid or already tracked.
    @discardableResult
    func addSymbol(provider: MarketProvider, rawSymbol: String) -> Bool {
        let token = "\(provider.rawValue):\(rawSymbol.trimmingCharacters(in: .whitespacesAndNewlines))"
        guard let symbol = TrackedSymbol(token: token),
              !symbols.contains(where: { $0.id == symbol.id }) else { return false }
        symbols.append(symbol)
        visibleSymbols.insert(symbol.id)
        saveConfig()
        restart()
        return true
    }

    func removeSymbol(id: String) {
        symbols.removeAll { $0.id == id }
        prices.removeValue(forKey: id)
        visibleSymbols.remove(id)
        resolvedBinanceMarkets.removeValue(forKey: id)
        saveConfig()
        restart()
    }

    func showsInMenuBar(_ symbol: TrackedSymbol) -> Bool {
        visibleSymbols.contains(symbol.id)
    }

    func setMenuBarVisibility(for symbol: TrackedSymbol, isVisible: Bool) {
        if isVisible {
            visibleSymbols.insert(symbol.id)
        } else {
            visibleSymbols.remove(symbol.id)
        }
        saveConfig()
    }

    private func runConnectionLoop() async {
        var retryDelaySeconds = 1.0

        while !Task.isCancelled {
            do {
                try await consumeStreams()
                retryDelaySeconds = 1.0
            } catch is CancellationError {
                break
            } catch {
                connectionStatus = "Disconnected"

                do {
                    try await Task.sleep(for: .seconds(retryDelaySeconds))
                } catch {
                    break
                }

                retryDelaySeconds = min(retryDelaySeconds * 2, 30)
            }
        }
    }

    private func consumeStreams() async throws {
        let marketSymbols = symbols.filter { $0.provider != .time && $0.provider != .spacer && $0.provider != .label }
        let groupedByProvider = Dictionary(grouping: marketSymbols, by: \.provider)

        if groupedByProvider.isEmpty {
            // Only time entries — nothing to stream, suspend until cancelled
            try await Task.sleep(for: .seconds(86400))
            return
        }

        connectionStatus = liveStatus(for: groupedByProvider)

        try await withThrowingTaskGroup(of: Void.self) { group in
            if let binanceSymbols = groupedByProvider[.binance], !binanceSymbols.isEmpty {
                group.addTask {
                    try await self.consumeBinanceStreams(for: binanceSymbols)
                }
            }

            if let hyperliquidSymbols = groupedByProvider[.hyperliquid], !hyperliquidSymbols.isEmpty {
                group.addTask {
                    try await self.consumeHyperliquidStreams(for: hyperliquidSymbols)
                }
            }

            try await group.waitForAll()
        }
    }

    private func liveStatus(for groupedByProvider: [MarketProvider: [TrackedSymbol]]) -> String {
        let providers = groupedByProvider.keys.sorted { $0.rawValue < $1.rawValue }
        let labels = providers.map(\.displayName)
        return labels.count > 1 ? "Live (\(labels.joined(separator: ", ")))" : "Live"
    }

    private func consumeBinanceStreams(for trackedSymbols: [TrackedSymbol]) async throws {
        let resolvedSymbols = try await withThrowingTaskGroup(of: ResolvedBinanceSymbol.self) { group in
            for trackedSymbol in trackedSymbols {
                group.addTask {
                    let market = try await self.resolveMarket(for: trackedSymbol)
                    return ResolvedBinanceSymbol(tracked: trackedSymbol, market: market)
                }
            }

            var resolved: [ResolvedBinanceSymbol] = []
            for try await symbol in group {
                resolved.append(symbol)
            }
            return resolved
        }

        let groupedSymbols = Dictionary(grouping: resolvedSymbols, by: \.market)

        if groupedSymbols.isEmpty {
            throw URLError(.badURL)
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (market, symbols) in groupedSymbols {
                let url = streamURL(for: market, symbols: symbols.map { $0.tracked.symbol })
                let trackedBySymbol = Dictionary(uniqueKeysWithValues: symbols.map { ($0.tracked.symbol, $0.tracked) })

                group.addTask {
                    try await Self.consumeBinanceStream(at: url) { payload in
                        await MainActor.run {
                            guard
                                let trackedSymbol = trackedBySymbol[payload.symbol],
                                let price = Double(payload.lastPrice),
                                let changePercent = Double(payload.priceChangePercent)
                            else {
                                return
                            }

                            self.updatePrice(for: trackedSymbol, price: price, changePercent: changePercent)
                        }
                    }
                }
            }

            try await group.waitForAll()
        }
    }

    private func consumeHyperliquidStreams(for trackedSymbols: [TrackedSymbol]) async throws {
        let requested = trackedSymbols.map { $0.symbol }.joined(separator: ", ")
        hyperliquidLogger.info("Starting Hyperliquid stream for: \(requested, privacy: .public)")

        let snapshot = try await loadHyperliquidSnapshot()
        let trackedByCoin = Dictionary(uniqueKeysWithValues: trackedSymbols.map { ($0.symbol, $0) })
        let requestedCoins = Set(trackedSymbols.map(\.symbol))
        let missingCoins = requestedCoins.subtracting(snapshot.availableCoins)

        hyperliquidLogger.info(
            "Hyperliquid meta loaded. requested=\(requestedCoins.count, privacy: .public) available=\(snapshot.availableCoins.count, privacy: .public) midPrices=\(snapshot.midPrices.count, privacy: .public) prevDayPrices=\(snapshot.prevDayPrices.count, privacy: .public)"
        )

        // xyz: coins not in the allMids snapshot are perps accessed via activeAssetCtx — don't throw for them
        let xyzPerpCoins = missingCoins.filter { $0.hasPrefix("xyz:") }
        let trulyMissingCoins = missingCoins.subtracting(xyzPerpCoins)

        if !trulyMissingCoins.isEmpty {
            hyperliquidLogger.error("Hyperliquid missing coins: \(trulyMissingCoins.sorted().joined(separator: ", "), privacy: .public)")
            throw URLError(.unsupportedURL)
        }

        if !xyzPerpCoins.isEmpty {
            hyperliquidLogger.info("Hyperliquid xyz: perp coins (will use activeAssetCtx): \(xyzPerpCoins.sorted().joined(separator: ", "), privacy: .public)")
        }

        updateHyperliquidPrices(
            midPrices: snapshot.midPrices,
            prevDayPrices: snapshot.prevDayPrices,
            trackedByCoin: trackedByCoin
        )

        hyperliquidLogger.info("Initial Hyperliquid prices applied for \(trackedSymbols.count, privacy: .public) symbols")

        try await Self.consumeHyperliquidStream(
            xyzPerpCoins: Array(xyzPerpCoins),
            onAllMidsUpdate: { [weak self] mids in
                guard let self else { return }
                hyperliquidLogger.debug("Hyperliquid allMids update with \(mids.count, privacy: .public) entries")

                var prices = mids.compactMapValues { Double($0) }
                for (atKey, alias) in snapshot.spotAliases {
                    if let price = prices[atKey] { prices[alias] = price }
                }

                await MainActor.run {
                    self.updateHyperliquidPrices(
                        midPrices: prices,
                        prevDayPrices: snapshot.prevDayPrices,
                        trackedByCoin: trackedByCoin
                    )
                }
            },
            onAssetCtxUpdate: { [weak self] coin, midPx, prevDayPx in
                await MainActor.run {
                    guard let self else { return }
                    self.xyzPerpPrevDayPrices[coin] = prevDayPx
                    self.updateHyperliquidPrices(
                        midPrices: [coin: midPx],
                        prevDayPrices: self.xyzPerpPrevDayPrices,
                        trackedByCoin: trackedByCoin
                    )
                }
            }
        )
    }

    private func updatePrice(for trackedSymbol: TrackedSymbol, price: Double, changePercent: Double) {
        prices[trackedSymbol.id] = PriceSnapshot(
            symbol: trackedSymbol.symbol,
            lastPrice: price,
            changePercent: changePercent
        )
        lastUpdated = Date()
    }

    private func updateHyperliquidPrices(
        midPrices: [String: Double],
        prevDayPrices: [String: Double],
        trackedByCoin: [String: TrackedSymbol]
    ) {
        for (coin, trackedSymbol) in trackedByCoin {
            guard let price = midPrices[coin] else {
                continue
            }

            let previousPrice = prevDayPrices[coin] ?? price
            let changePercent = previousPrice > 0 ? ((price - previousPrice) / previousPrice) * 100 : 0
            updatePrice(for: trackedSymbol, price: price, changePercent: changePercent)
        }
    }

    private func resolveMarket(for trackedSymbol: TrackedSymbol) async throws -> BinanceMarket {
        if let cached = resolvedBinanceMarkets[trackedSymbol.id] {
            return cached
        }

        if try await symbolExists(trackedSymbol.symbol, in: .spot) {
            resolvedBinanceMarkets[trackedSymbol.id] = .spot
            return .spot
        }

        if try await symbolExists(trackedSymbol.symbol, in: .futures) {
            resolvedBinanceMarkets[trackedSymbol.id] = .futures
            return .futures
        }

        throw URLError(.unsupportedURL)
    }

    private func symbolExists(_ symbol: String, in market: BinanceMarket) async throws -> Bool {
        var components = URLComponents(url: market.tickerProbeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "symbol", value: symbol),
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let (_, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.statusCode == 200
    }

    private static func consumeBinanceStream(
        at url: URL,
        onPayload: @escaping @Sendable (BinanceTickerPayload) async -> Void
    ) async throws {
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()

        defer {
            task.cancel(with: .goingAway, reason: nil)
        }

        while !Task.isCancelled {
            let message = try await task.receive()
            let envelope = try decodeTickerPayload(from: message)
            await onPayload(envelope.data)
        }
    }

    private static func decodeTickerPayload(from message: URLSessionWebSocketTask.Message) throws -> BinanceCombinedTicker {
        let data: Data

        switch message {
        case .data(let value):
            data = value
        case .string(let value):
            data = Data(value.utf8)
        @unknown default:
            throw URLError(.cannotParseResponse)
        }

        return try JSONDecoder().decode(BinanceCombinedTicker.self, from: data)
    }

    private func streamURL(for market: BinanceMarket, symbols: [String]) -> URL {
        let streams = symbols
            .map { $0.lowercased() + "@ticker" }
            .joined(separator: "/")

        return URL(string: market.websocketBaseURL + streams)!
    }

    private func loadHyperliquidSnapshot() async throws -> HyperliquidMarketSnapshot {
        let url = URL(string: "https://api.hyperliquid.xyz/info")!

        func fetchInfo(type: String) async throws -> HyperliquidInfoResponse {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["type": type])

            hyperliquidLogger.info("Fetching Hyperliquid \(type, privacy: .public) snapshot")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                hyperliquidLogger.error("Hyperliquid \(type, privacy: .public) request failed: not HTTPURLResponse")
                throw URLError(.badServerResponse)
            }
            let statusCode = httpResponse.statusCode
            guard 200..<300 ~= statusCode else {
                hyperliquidLogger.error("Hyperliquid \(type, privacy: .public) request failed with status \(statusCode, privacy: .public)")
                throw URLError(.badServerResponse)
            }
            hyperliquidLogger.info("Hyperliquid \(type, privacy: .public) HTTP \(statusCode, privacy: .public), bytes=\(data.count, privacy: .public)")
            return try JSONDecoder().decode(HyperliquidInfoResponse.self, from: data)
        }

        async let perpsResponse = fetchInfo(type: "metaAndAssetCtxs")
        async let spotResponse = fetchInfo(type: "spotMetaAndAssetCtxs")
        let (perps, spot) = try await (perpsResponse, spotResponse)

        var availableCoins: Set<String> = []
        var midPrices: [String: Double] = [:]
        var prevDayPrices: [String: Double] = [:]

        // Build index→tokenName map for spot so we can resolve @N universe names to xyz:NAME aliases
        let spotTokensByIndex: [Int: String] = Dictionary(
            uniqueKeysWithValues: (spot.meta.tokens ?? []).map { ($0.index, $0.name) }
        )

        // @N key → xyz:NAME (used to expand live WebSocket updates)
        var spotAliases: [String: String] = [:]

        for decoded in [perps, spot] {
            for (index, assetContext) in decoded.assetContexts.enumerated() {
                let coin = assetContext.coin ?? (index < decoded.meta.universe.count ? decoded.meta.universe[index].name : nil)
                guard let coin else { continue }

                availableCoins.insert(coin)

                if let midPx = assetContext.midPx, let price = Double(midPx) {
                    midPrices[coin] = price
                }

                if let prevDayPx = assetContext.prevDayPx, let price = Double(prevDayPx) {
                    prevDayPrices[coin] = price
                }

                // For spot @N entries, also register an xyz:TOKENNAME alias so users can
                // subscribe using the same names shown on the Hyperliquid frontend.
                if coin.hasPrefix("@"),
                   index < decoded.meta.universe.count,
                   let baseTokenIndex = decoded.meta.universe[index].tokens?.first,
                   let tokenName = spotTokensByIndex[baseTokenIndex] {
                    let alias = "xyz:\(tokenName)"
                    availableCoins.insert(alias)
                    spotAliases[coin] = alias
                    if let price = midPrices[coin] { midPrices[alias] = price }
                    if let price = prevDayPrices[coin] { prevDayPrices[alias] = price }
                }
            }
        }

        hyperliquidLogger.info(
            "Decoded Hyperliquid snapshot. perps=\(perps.meta.universe.count, privacy: .public) spot=\(spot.meta.universe.count, privacy: .public) availableCoins=\(availableCoins.count, privacy: .public)"
        )

        return HyperliquidMarketSnapshot(
            availableCoins: availableCoins,
            midPrices: midPrices,
            prevDayPrices: prevDayPrices,
            spotAliases: spotAliases
        )
    }

    private static func consumeHyperliquidStream(
        xyzPerpCoins: [String] = [],
        onAllMidsUpdate: @escaping @Sendable ([String: String]) async -> Void,
        onAssetCtxUpdate: @escaping @Sendable (String, Double, Double) async -> Void
    ) async throws {
        let streamURL = URL(string: "wss://api.hyperliquid.xyz/ws")!
        hyperliquidLogger.info("Opening Hyperliquid websocket at \(streamURL.absoluteString, privacy: .public)")
        let task = URLSession.shared.webSocketTask(with: streamURL)
        task.resume()

        defer {
            hyperliquidLogger.info("Closing Hyperliquid websocket")
            task.cancel(with: .goingAway, reason: nil)
        }

        func send(_ payload: [String: Any]) throws {
            let data = try JSONSerialization.data(withJSONObject: payload)
            guard let message = String(data: data, encoding: .utf8) else {
                throw URLError(.cannotParseResponse)
            }
            Task { try await task.send(.string(message)) }
        }

        try send(["method": "subscribe", "subscription": ["type": "allMids"]])
        hyperliquidLogger.info("Subscribed to allMids")

        for coin in xyzPerpCoins {
            try send(["method": "subscribe", "subscription": ["type": "activeAssetCtx", "coin": coin]])
            hyperliquidLogger.info("Subscribed to activeAssetCtx for \(coin, privacy: .public)")
        }

        while !Task.isCancelled {
            let incoming = try await task.receive()
            let rawData: Data
            switch incoming {
            case .data(let d): rawData = d
            case .string(let s): rawData = Data(s.utf8)
            @unknown default: continue
            }

            guard let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any],
                  let channel = json["channel"] as? String else { continue }

            if channel == "allMids" {
                let envelope = try decodeHyperliquidMessage(from: incoming)
                if let mids = envelope.data {
                    hyperliquidLogger.debug("Hyperliquid allMids symbolCount=\(mids.count, privacy: .public)")
                    await onAllMidsUpdate(mids)
                }
            } else if channel == "activeAssetCtx",
                      let data = json["data"] as? [String: Any],
                      let coin = data["coin"] as? String,
                      let ctx = data["ctx"] as? [String: Any],
                      let midPxStr = ctx["midPx"] as? String,
                      let midPx = Double(midPxStr) {
                let prevDayPx = (ctx["prevDayPx"] as? String).flatMap(Double.init) ?? midPx
                hyperliquidLogger.debug("Hyperliquid activeAssetCtx coin=\(coin, privacy: .public) midPx=\(midPx, privacy: .public)")
                await onAssetCtxUpdate(coin, midPx, prevDayPx)
            } else {
                hyperliquidLogger.debug("Hyperliquid message ignored channel=\(channel, privacy: .public)")
            }
        }
    }

    private static func decodeHyperliquidMessage(from message: URLSessionWebSocketTask.Message) throws -> HyperliquidWebSocketMessage {
        let data: Data

        switch message {
        case .data(let value):
            data = value
        case .string(let value):
            data = Data(value.utf8)
        @unknown default:
            hyperliquidLogger.error("Received unknown Hyperliquid websocket message type")
            throw URLError(.cannotParseResponse)
        }

        guard let rawString = String(data: data, encoding: .utf8) else {
            hyperliquidLogger.error("Failed to convert Hyperliquid websocket message to string, bytes=\(data.count, privacy: .public)")
            throw URLError(.cannotParseResponse)
        }

        hyperliquidLogger.debug("Hyperliquid websocket raw message: \(rawString, privacy: .public)")

        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = object as? [String: Any] else {
            hyperliquidLogger.debug("Hyperliquid websocket message was not a dictionary")
            return HyperliquidWebSocketMessage(channel: nil, data: nil)
        }

        let channel = dictionary["channel"] as? String
        let dataDictionary = dictionary["data"] as? [String: Any]
        let mids = dataDictionary?.compactMapValues { value -> String? in
            if let string = value as? String {
                return string
            }

            if let number = value as? NSNumber {
                return number.stringValue
            }

            return nil
        }

        return HyperliquidWebSocketMessage(channel: channel, data: mids)
    }

    private static func parseSymbols(from input: String) -> [TrackedSymbol] {
        let separators = CharacterSet(charactersIn: ",\n ")

        let tokens = input
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        var symbols: [TrackedSymbol] = []

        for token in tokens {
            guard let trackedSymbol = TrackedSymbol(token: token) else {
                continue
            }

            if seen.insert(trackedSymbol.id).inserted {
                symbols.append(trackedSymbol)
            }
        }

        return symbols
    }
}

private struct BinanceCombinedTicker: Decodable {
    let data: BinanceTickerPayload
}

private struct BinanceTickerPayload: Decodable, Sendable {
    let symbol: String
    let lastPrice: String
    let priceChangePercent: String

    enum CodingKeys: String, CodingKey {
        case symbol = "s"
        case lastPrice = "c"
        case priceChangePercent = "P"
    }
}

private struct HyperliquidInfoResponse: Decodable {
    let meta: HyperliquidMeta
    let assetContexts: [HyperliquidAssetContext]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        meta = try container.decode(HyperliquidMeta.self)
        assetContexts = try container.decode([HyperliquidAssetContext].self)
    }
}

private struct HyperliquidMeta: Decodable {
    let universe: [HyperliquidUniverseAsset]
    let tokens: [HyperliquidToken]?
}

private struct HyperliquidUniverseAsset: Decodable {
    let name: String
    let tokens: [Int]?
}

private struct HyperliquidToken: Decodable {
    let name: String
    let index: Int
}

private struct HyperliquidAssetContext: Decodable {
    let coin: String?
    let midPx: String?
    let prevDayPx: String?
}

private struct HyperliquidWebSocketMessage {
    let channel: String?
    let data: [String: String]?
}

private enum PriceFormatter {
    static func string(from value: Double) -> String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.groupingSeparator = ""
        formatter.decimalSeparator = "."
        formatter.positivePrefix = "$"
        formatter.negativePrefix = "-$"
        return formatter.string(from: value as NSNumber)
    }
}
