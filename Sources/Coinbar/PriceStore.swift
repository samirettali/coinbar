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
                try await consumeStream()
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

    private func consumeStream() async throws {
        connectionStatus = "Connecting..."

        let task = URLSession.shared.webSocketTask(with: streamURL)
        task.resume()

        defer {
            task.cancel(with: .goingAway, reason: nil)
        }

        connectionStatus = "Live"

        while !Task.isCancelled {
            let message = try await task.receive()
            let envelope = try decodeTickerPayload(from: message)
            let payload = envelope.data

            guard
                let price = Double(payload.lastPrice),
                let changePercent = Double(payload.priceChangePercent)
            else {
                continue
            }

            prices[payload.symbol] = PriceSnapshot(
                symbol: payload.symbol,
                lastPrice: price,
                changePercent: changePercent
            )
            lastUpdated = Date()
        }
    }

    private func decodeTickerPayload(from message: URLSessionWebSocketTask.Message) throws -> BinanceCombinedTicker {
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

    private var streamURL: URL {
        let streams = symbols
            .map(\.symbol)
            .map { $0.lowercased() + "@ticker" }
            .joined(separator: "/")

        return URL(string: "wss://stream.binance.com:9443/stream?streams=\(streams)")!
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

private struct BinanceTickerPayload: Decodable {
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
