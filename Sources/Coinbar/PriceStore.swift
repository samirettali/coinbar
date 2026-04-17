import Foundation
import SwiftUI

struct TrackedSymbol: Identifiable {
    let symbol: String
    let displayName: String

    var id: String { symbol }

    static let defaults: [TrackedSymbol] = [
        TrackedSymbol(symbol: "BTCUSDT", displayName: "BTC"),
        TrackedSymbol(symbol: "ETHUSDT", displayName: "ETH"),
        TrackedSymbol(symbol: "SOLUSDT", displayName: "SOL"),
    ]

    init(symbol: String, displayName: String? = nil) {
        self.symbol = symbol
        self.displayName = displayName ?? TrackedSymbol.defaultDisplayName(for: symbol)
    }

    private static func defaultDisplayName(for symbol: String) -> String {
        if symbol.hasSuffix("USDT") {
            return String(symbol.dropLast(4))
        }

        return symbol
    }
}

struct PriceSnapshot {
    let symbol: String
    let lastPrice: Double
    let changePercent: Double

    var formattedPrice: String {
        CurrencyFormatter.shared.string(from: lastPrice as NSNumber) ?? "--"
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

private enum BinanceMarket: String {
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

private struct ResolvedSymbol {
    let tracked: TrackedSymbol
    let market: BinanceMarket
}

@MainActor
final class PriceStore: ObservableObject {
    @Published private(set) var prices: [String: PriceSnapshot] = [:]
    @Published private(set) var connectionStatus = "Connecting..."
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var symbols: [TrackedSymbol]
    @Published private(set) var visibleSymbols: Set<String>

    private let defaults = UserDefaults.standard
    private let symbolsKey = "trackedSymbols"
    private let visibleSymbolsKey = "visibleMenuBarSymbols"

    private var streamTask: Task<Void, Never>?
    private var resolvedMarkets: [String: BinanceMarket] = [:]

    init(symbols: [TrackedSymbol]) {
        let persisted = Self.loadSymbols(defaults: UserDefaults.standard, key: symbolsKey)
        let resolvedSymbols = persisted.isEmpty ? symbols : persisted
        let persistedVisible = Self.loadVisibleSymbols(defaults: UserDefaults.standard, key: visibleSymbolsKey)

        self.symbols = resolvedSymbols
        self.visibleSymbols = persistedVisible.isEmpty
            ? Set(resolvedSymbols.prefix(2).map(\.symbol))
            : persistedVisible.intersection(Set(resolvedSymbols.map(\.symbol)))

        start()
    }

    var menuBarTitle: String {
        let parts = symbols.filter { visibleSymbols.contains($0.symbol) }.map { symbol in
            let value = prices[symbol.symbol]?.formattedPrice ?? "--"
            return "\(shortSymbol(for: symbol.symbol)) \(value)"
        }

        return parts.isEmpty ? "Coinbar" : parts.joined(separator: "  ")
    }

    func start() {
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
        prices = prices.filter { price in
            parsed.contains(where: { $0.symbol == price.key })
        }
        let validSymbols = Set(parsed.map(\.symbol))
        visibleSymbols = visibleSymbols.intersection(validSymbols)
        if visibleSymbols.isEmpty {
            visibleSymbols = Set(parsed.prefix(2).map(\.symbol))
        }
        resolvedMarkets = resolvedMarkets.filter { validSymbols.contains($0.key) }
        lastUpdated = nil
        defaults.set(parsed.map(\.symbol), forKey: symbolsKey)
        defaults.set(Array(visibleSymbols), forKey: visibleSymbolsKey)
        restart()
    }

    func editableSymbolsText() -> String {
        symbols.map(\.symbol).joined(separator: "\n")
    }

    func showsInMenuBar(_ symbol: String) -> Bool {
        visibleSymbols.contains(symbol)
    }

    func setMenuBarVisibility(for symbol: String, isVisible: Bool) {
        if isVisible {
            visibleSymbols.insert(symbol)
        } else {
            visibleSymbols.remove(symbol)
        }

        defaults.set(Array(visibleSymbols), forKey: visibleSymbolsKey)
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
        connectionStatus = "Resolving symbols..."
        let resolvedSymbols = try await resolveSymbols()
        let groupedSymbols = Dictionary(grouping: resolvedSymbols, by: \.market)

        if groupedSymbols.isEmpty {
            throw URLError(.badURL)
        }

        connectionStatus = groupedSymbols.count > 1 ? "Live (spot + futures)" : "Live"

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (market, symbols) in groupedSymbols {
                let url = streamURL(for: market, symbols: symbols.map(\.tracked.symbol))
                group.addTask {
                    try await Self.consumeStream(at: url) { payload in
                        await MainActor.run {
                            guard
                                let price = Double(payload.lastPrice),
                                let changePercent = Double(payload.priceChangePercent)
                            else {
                                return
                            }

                            self.prices[payload.symbol] = PriceSnapshot(
                                symbol: payload.symbol,
                                lastPrice: price,
                                changePercent: changePercent
                            )
                            self.lastUpdated = Date()
                        }
                    }
                }
            }

            try await group.waitForAll()
        }
    }

    private func resolveSymbols() async throws -> [ResolvedSymbol] {
        try await withThrowingTaskGroup(of: ResolvedSymbol.self) { group in
            for trackedSymbol in symbols {
                group.addTask {
                    let market = try await self.resolveMarket(for: trackedSymbol.symbol)
                    return ResolvedSymbol(tracked: trackedSymbol, market: market)
                }
            }

            var resolved: [ResolvedSymbol] = []
            for try await symbol in group {
                resolved.append(symbol)
            }
            return resolved
        }
    }

    private func resolveMarket(for symbol: String) async throws -> BinanceMarket {
        if let cached = resolvedMarkets[symbol] {
            return cached
        }

        if try await symbolExists(symbol, in: .spot) {
            resolvedMarkets[symbol] = .spot
            return .spot
        }

        if try await symbolExists(symbol, in: .futures) {
            resolvedMarkets[symbol] = .futures
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

    private static func consumeStream(
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

    private func shortSymbol(for symbol: String) -> String {
        if symbol.hasSuffix("USDT") {
            return String(symbol.dropLast(4))
        }

        return symbol
    }

    private static func loadSymbols(defaults: UserDefaults, key: String) -> [TrackedSymbol] {
        guard let stored = defaults.stringArray(forKey: key) else {
            return []
        }

        return stored.map { TrackedSymbol(symbol: $0) }
    }

    private static func loadVisibleSymbols(defaults: UserDefaults, key: String) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    private static func parseSymbols(from input: String) -> [TrackedSymbol] {
        let separators = CharacterSet(charactersIn: ",\n ")

        let tokens = input
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        var symbols: [TrackedSymbol] = []

        for token in tokens where seen.insert(token).inserted {
            symbols.append(TrackedSymbol(symbol: token))
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

private enum CurrencyFormatter {
    static let shared: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()
}
