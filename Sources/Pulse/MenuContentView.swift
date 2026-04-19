import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: PriceStore
    @State private var addProvider: MarketProvider = .binance
    @State private var addText = ""
    @State private var addFailed = false
    @State private var isAdding = false
    @State private var draggingSymbol: TrackedSymbol?
    @State private var renamingId: String? = nil
    @State private var renameText = ""
    @State private var showingSettings = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            listView
                .offset(x: showingSettings ? -280 : 0)
                .animation(.easeInOut(duration: 0.2), value: showingSettings)

            settingsPanel
                .offset(x: showingSettings ? 0 : 280)
                .animation(.easeInOut(duration: 0.2), value: showingSettings)
        }
        .frame(width: 260)
        .clipped()
        .background(WindowPositionPin())
        .onDisappear {
            if let id = renamingId {
                store.renameSymbol(id: id, newName: renameText)
                renamingId = nil
            }
        }
    }

    private var settingsPanel: some View {
        SettingsView(store: store) {
            withAnimation(.easeInOut(duration: 0.2)) { showingSettings = false }
        }
        .padding(14)
        .frame(width: 260, alignment: .topLeading)
    }

    private var listView: some View {
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

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingSettings.toggle()
                        }
                    } label: {
                        Image(systemName: showingSettings ? "gearshape.fill" : "gearshape")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
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
            if renamingId == symbol.id {
                TransparentTextField(
                    text: $renameText,
                    font: NSFont(name: "JetBrainsMono Nerd Font", size: 12) ?? .systemFont(ofSize: 12, weight: .semibold),
                    color: .secondaryLabelColor,
                    placeholder: symbol.displayName,
                    onCommit: { commitRename(for: symbol) },
                    onCancel: { renamingId = nil }
                )
                .frame(maxWidth: .infinity)
            } else {
                Text(store.displayName(for: symbol))
                    .font(AppFont.uiFont(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contextMenu {
                        Button("Rename") { startRename(for: symbol) }
                        Divider()
                        Button("Delete", role: .destructive) {
                            store.removeSymbol(id: symbol.id)
                        }
                    }
            }
        } else {
            PriceRowView(
                symbol: symbol,
                displayName: store.displayName(for: symbol),
                isRenaming: renamingId == symbol.id,
                renameBinding: $renameText,
                snapshot: store.prices[symbol.id],
                timeText: symbol.provider == .time ? store.timeText(for: symbol.symbol) : nil,
                timeDiffText: symbol.provider == .time ? store.timeDifferenceText(for: symbol.symbol) : nil,
                isVisibleInMenuBar: store.showsInMenuBar(symbol),
                onVisibilityChange: { isVisible in
                    store.setMenuBarVisibility(for: symbol, isVisible: isVisible)
                },
                onRenameRequest: { startRename(for: symbol) },
                onCommitRename: { commitRename(for: symbol) },
                onCancelRename: { renamingId = nil },
                onDelete: {
                    store.removeSymbol(id: symbol.id)
                }
            )
        }
    }

    private func startRename(for symbol: TrackedSymbol) {
        renameText = store.displayName(for: symbol)
        renamingId = symbol.id
    }

    private func commitRename(for symbol: TrackedSymbol) {
        store.renameSymbol(id: symbol.id, newName: renameText)
        renamingId = nil
        renameText = ""
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
    let displayName: String
    let isRenaming: Bool
    let renameBinding: Binding<String>
    let snapshot: PriceSnapshot?
    let timeText: String?
    let timeDiffText: String?
    let isVisibleInMenuBar: Bool

    let onVisibilityChange: @MainActor @Sendable (Bool) -> Void
    let onRenameRequest: @MainActor @Sendable () -> Void
    let onCommitRename: @MainActor @Sendable () -> Void
    let onCancelRename: @MainActor @Sendable () -> Void
    let onDelete: @MainActor @Sendable () -> Void

    @State private var isMenuOpen = false

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    TransparentTextField(
                        text: renameBinding,
                        font: NSFont(name: "JetBrainsMono Nerd Font", size: 13) ?? .boldSystemFont(ofSize: 13),
                        color: .labelColor,
                        placeholder: symbol.displayName,
                        onCommit: onCommitRename,
                        onCancel: onCancelRename
                    )

                } else {
                    Text(displayName)
                        .font(AppFont.uiFont(size: 13, weight: .semibold))
                }

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
                    menu.addItem(ClosureMenuItem(title: "Rename") { onRenameRequest() })
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

private class TransparentNSTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if let editor = currentEditor() as? NSTextView {
            editor.drawsBackground = false
            editor.backgroundColor = .clear
        }
        return result
    }
}

private struct TransparentTextField: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    let color: NSColor
    var placeholder: String = ""
    var onCommit: () -> Void = {}
    var onCancel: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> TransparentNSTextField {
        let field = TransparentNSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.font = font
        field.textColor = color
        field.placeholderString = placeholder
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: TransparentNSTextField, context: Context) {
        if nsView.stringValue != text { nsView.stringValue = text }
        nsView.font = font
        nsView.textColor = color
        nsView.placeholderString = placeholder
        context.coordinator.parent = self
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TransparentTextField
        var didExplicitlyFinish = false
        init(_ parent: TransparentTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                parent.text = field.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                didExplicitlyFinish = true
                parent.onCommit()
                return true
            }
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                didExplicitlyFinish = true
                parent.onCancel()
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            if !didExplicitlyFinish {
                parent.onCommit()
            }
            didExplicitlyFinish = false
        }
    }
}

private struct WindowPositionPin: NSViewRepresentable {
    func makeNSView(context: Context) -> PinView { PinView() }
    func updateNSView(_ nsView: PinView, context: Context) {}

    class PinView: NSView {
        private var moveObserver: NSObjectProtocol?
        private var resizeObserver: NSObjectProtocol?
        private var showObserver: NSObjectProtocol?
        // Top-left corner in screen coordinates (y increases upward on macOS).
        // Pinning the top keeps the popup anchored just below the menu bar
        // and makes it grow downward when content is added.
        private var pinnedTopLeft: NSPoint?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            teardown()
            guard let window else { return }

            showObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                guard let self, let window else { return }
                MainActor.assumeIsolated { self.pinnedTopLeft = nil }
                DispatchQueue.main.async { [weak self, weak window] in
                    guard let self, let window else { return }
                    MainActor.assumeIsolated {
                        let f = window.frame
                        self.pinnedTopLeft = NSPoint(x: f.origin.x, y: f.origin.y + f.size.height)
                    }
                }
            }

            let applyPin: @Sendable () -> Void = { [weak self, weak window] in
                guard let self, let window else { return }
                let pinned = MainActor.assumeIsolated { self.pinnedTopLeft }
                guard let pinned else { return }
                MainActor.assumeIsolated {
                    let f = window.frame
                    let target = NSPoint(x: pinned.x, y: pinned.y - f.size.height)
                    if f.origin != target { window.setFrameOrigin(target) }
                }
            }

            moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: window, queue: .main
            ) { _ in applyPin() }

            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window, queue: .main
            ) { _ in applyPin() }
        }

        private func teardown() {
            if let o = moveObserver { NotificationCenter.default.removeObserver(o) }
            if let o = resizeObserver { NotificationCenter.default.removeObserver(o) }
            if let o = showObserver { NotificationCenter.default.removeObserver(o) }
            moveObserver = nil
            resizeObserver = nil
            showObserver = nil
            pinnedTopLeft = nil
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
