import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: PriceStore
    @State private var isEditingSymbols = false
    @State private var symbolsDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(store.symbols) { symbol in
                PriceRowView(
                    symbol: symbol,
                    snapshot: store.prices[symbol.symbol],
                    isVisibleInMenuBar: store.showsInMenuBar(symbol.symbol),
                    onVisibilityChange: { isVisible in
                        store.setMenuBarVisibility(for: symbol.symbol, isVisible: isVisible)
                    }
                )
            }

            Divider()

            if isEditingSymbols {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tracked Symbols")
                        .font(AppFont.uiFont(size: 12, weight: .semibold))

                    Text("One Binance symbol per line")
                        .font(AppFont.uiFont(size: 11))
                        .foregroundStyle(.secondary)

                    TextEditor(text: $symbolsDraft)
                        .font(AppFont.uiFont(size: 12))
                        .frame(height: 90)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2))
                        }

                    HStack {
                        Button("Cancel") {
                            isEditingSymbols = false
                            symbolsDraft = store.editableSymbolsText()
                        }

                        Spacer()

                        Button("Save") {
                            store.updateSymbols(from: symbolsDraft)
                            symbolsDraft = store.editableSymbolsText()
                            isEditingSymbols = false
                        }
                    }
                }

                Divider()
            }

            HStack {
                Text(store.connectionStatus)
                    .font(AppFont.uiFont(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                if let timestamp = store.lastUpdated {
                    Text(timestamp.formatted(date: .omitted, time: .standard))
                        .font(AppFont.uiFont(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button(isEditingSymbols ? "Editing..." : "Symbols") {
                    symbolsDraft = store.editableSymbolsText()
                    isEditingSymbols.toggle()
                }
                .disabled(isEditingSymbols)

                Button("Reconnect") {
                    store.restart()
                }
                .disabled(isEditingSymbols)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 260)
        .onAppear {
            symbolsDraft = store.editableSymbolsText()
        }
    }
}

private struct PriceRowView: View {
    let symbol: TrackedSymbol
    let snapshot: PriceSnapshot?
    let isVisibleInMenuBar: Bool
    let onVisibilityChange: (Bool) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Toggle(isOn: Binding(
                get: { isVisibleInMenuBar },
                set: onVisibilityChange
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(symbol.displayName)
                    .font(AppFont.uiFont(size: 13, weight: .semibold))

                Text(symbol.symbol)
                    .font(AppFont.uiFont(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(snapshot?.formattedPrice ?? "--")
                    .font(AppFont.uiFont(size: 13, weight: .medium))

                Text(snapshot?.formattedPercent ?? "--")
                    .font(AppFont.uiFont(size: 11))
                    .foregroundStyle(snapshot?.changeColor ?? .secondary)
            }
        }
    }
}
