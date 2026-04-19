import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: PriceStore
    @State private var addProvider: MarketProvider = .binance
    @State private var addText = ""
    @State private var addFailed = false
    @State private var isAdding = false
    @State private var draggingSymbol: TrackedSymbol?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(store.symbols) { symbol in
                    rowView(for: symbol)
                        .listRowInsets(EdgeInsets(
                            top: symbol.provider == .spacer ? 2 : 4,
                            leading: 0,
                            bottom: symbol.provider == .spacer ? 2 : 4,
                            trailing: 0
                        ))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .opacity(draggingSymbol?.id == symbol.id ? 0.4 : 1)
                        .onDrag({
                            draggingSymbol = symbol
                            return NSItemProvider(object: symbol.id as NSString)
                        }, preview: {
                            Color.clear.frame(width: 1, height: 1)
                        })
                        .onDrop(of: [.text], delegate: ReorderDropDelegate(
                            target: symbol,
                            store: store,
                            dragging: $draggingSymbol
                        ))
                }

                if isAdding {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            TextField(addProvider.symbolPlaceholder, text: $addText)
                                .font(AppFont.uiFont(size: 12))
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { tryAdd() }

                            Button("Add") { tryAdd() }
                                .disabled(addText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if addFailed {
                            Text("Invalid \(addProvider.displayName) symbol")
                                .font(AppFont.uiFont(size: 11))
                                .foregroundStyle(.red)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                HStack {
                    if isAdding {
                        Button {
                            isAdding = false
                            addText = ""
                            addFailed = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .onHover { inside in
                            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                    } else {
                        Menu {
                            Button("Binance Pair") {
                                addProvider = .binance
                                addText = ""
                                addFailed = false
                                isAdding = true
                            }
                            Button("Hyperliquid Pair") {
                                addProvider = .hyperliquid
                                addText = ""
                                addFailed = false
                                isAdding = true
                            }
                            Button("Timezone") {
                                addProvider = .time
                                addText = ""
                                addFailed = false
                                isAdding = true
                            }
                            Button("Label") {
                                addProvider = .label
                                addText = ""
                                addFailed = false
                                isAdding = true
                            }
                            Divider()
                            Button("Separator") {
                                store.addSpacer()
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .onHover { inside in
                            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            }
            .listStyle(.plain)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 260)
        .onAppear { store.isMenuOpen = true }
        .onDisappear { store.isMenuOpen = false }
    }

    @ViewBuilder
    private func rowView(for symbol: TrackedSymbol) -> some View {
        if symbol.provider == .spacer {
            Divider()
                .frame(height: 17)
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        store.removeSymbol(id: symbol.id)
                    }
                }
        } else if symbol.provider == .label {
            Text(symbol.symbol)
                .font(AppFont.uiFont(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        store.removeSymbol(id: symbol.id)
                    }
                }
        } else {
            PriceRowView(
                symbol: symbol,
                snapshot: store.prices[symbol.id],
                timeText: symbol.provider == .time ? store.timeText(for: symbol.symbol) : nil,
                timeDiffText: symbol.provider == .time ? store.timeDifferenceText(for: symbol.symbol) : nil,
                isVisibleInMenuBar: store.showsInMenuBar(symbol),
                onVisibilityChange: { isVisible in
                    store.setMenuBarVisibility(for: symbol, isVisible: isVisible)
                },
                onDelete: {
                    store.removeSymbol(id: symbol.id)
                }
            )
        }
    }

    private func tryAdd() {
        let trimmed = addText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if addProvider == .label {
            store.addLabel(text: trimmed)
            addText = ""
            addFailed = false
            isAdding = false
            return
        }
        if store.addSymbol(provider: addProvider, rawSymbol: trimmed) {
            addText = ""
            addFailed = false
            isAdding = false
        } else {
            addFailed = true
        }
    }
}

private struct PriceRowView: View {
    let symbol: TrackedSymbol
    let snapshot: PriceSnapshot?
    let timeText: String?
    let timeDiffText: String?
    let isVisibleInMenuBar: Bool
    let onVisibilityChange: @MainActor @Sendable (Bool) -> Void
    let onDelete: @MainActor @Sendable () -> Void

    @State private var isMenuOpen = false

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(symbol.displayName)
                    .font(AppFont.uiFont(size: 13, weight: .semibold))

                Text(symbol.provider.displayName)
                    .font(AppFont.uiFont(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let timeText {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(timeText)
                        .font(AppFont.uiFont(size: 13, weight: .medium))
                    if let timeDiffText {
                        Text(timeDiffText)
                            .font(AppFont.uiFont(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(snapshot?.formattedPrice ?? "--")
                        .font(AppFont.uiFont(size: 13, weight: .medium))

                    Text(snapshot?.formattedPercent ?? "--")
                        .font(AppFont.uiFont(size: 10))
                        .foregroundStyle(snapshot?.changeColor ?? .secondary)
                }
            }
        }
        .opacity(isMenuOpen ? 0.4 : 1)
        .animation(.easeInOut(duration: 0.15), value: isMenuOpen)
        .overlay(
            ContextMenuCapture(
                buildMenu: { menu in
                    menu.addItem(ClosureMenuItem(
                        title: isVisibleInMenuBar ? "Hide from Menu Bar" : "Show in Menu Bar"
                    ) { onVisibilityChange(!isVisibleInMenuBar) })
                    menu.addItem(.separator())
                    menu.addItem(ClosureMenuItem(title: "Delete", isDestructive: true) { onDelete() })
                },
                onOpen: { isMenuOpen = true },
                onClose: { isMenuOpen = false }
            )
        )
        .onTapGesture {
            if let url = symbol.provider.tradeURL(for: symbol.symbol) {
                NSWorkspace.shared.open(url)
            }
        }
        .onHover { inside in
            if symbol.provider.tradeURL(for: symbol.symbol) != nil {
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let closure: @MainActor () -> Void

    init(title: String, isDestructive: Bool = false, action closure: @escaping @MainActor () -> Void) {
        self.closure = closure
        super.init(title: title, action: #selector(execute), keyEquivalent: "")
        self.target = self
        if isDestructive {
            attributedTitle = NSAttributedString(
                string: title,
                attributes: [.foregroundColor: NSColor.systemRed]
            )
        }
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func execute() {
        let c = closure
        MainActor.assumeIsolated { c() }
    }
}

private struct ContextMenuCapture: NSViewRepresentable {
    let buildMenu: @MainActor (NSMenu) -> Void
    let onOpen: @MainActor () -> Void
    let onClose: @MainActor () -> Void

    func makeNSView(context: Context) -> ContextMenuNSView { ContextMenuNSView() }

    func updateNSView(_ nsView: ContextMenuNSView, context: Context) {
        nsView.buildMenu = buildMenu
        nsView.onOpen = onOpen
        nsView.onClose = onClose
    }

    class ContextMenuNSView: NSView {
        var buildMenu: (@MainActor (NSMenu) -> Void)?
        var onOpen: (@MainActor () -> Void)?
        var onClose: (@MainActor () -> Void)?

        override func rightMouseDown(with event: NSEvent) {
            let menu = NSMenu()
            MainActor.assumeIsolated {
                buildMenu?(menu)
                onOpen?()
            }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            MainActor.assumeIsolated { onClose?() }
        }
    }
}

private struct ReorderDropDelegate: DropDelegate {
    let target: TrackedSymbol
    let store: PriceStore
    @Binding var dragging: TrackedSymbol?

    func dropEntered(info: DropInfo) {
        guard
            let dragging,
            dragging.id != target.id,
            let from = store.symbols.firstIndex(where: { $0.id == dragging.id }),
            let to = store.symbols.firstIndex(where: { $0.id == target.id })
        else { return }
        MainActor.assumeIsolated {
            withAnimation(.none) {
                store.moveSymbol(from: IndexSet(integer: from), to: to > from ? to + 1 : to)
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
