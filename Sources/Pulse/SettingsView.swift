import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: PriceStore
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Back")
                        .font(AppFont.uiFont(size: 11, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

            VStack(spacing: 10) {
                    HStack {
                        Text("Divider")
                            .font(AppFont.uiFont(size: 12))
                        Spacer()
                        TextField("none", text: Binding(
                            get: { store.menuBarDivider },
                            set: { store.setMenuBarDivider($0) }
                        ))
                        .font(AppFont.uiFont(size: 12))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    }

                    HStack {
                        Text("Gap")
                            .font(AppFont.uiFont(size: 12))
                        Spacer()
                        Stepper(
                            value: Binding(
                                get: { store.menuBarGap },
                                set: { store.setMenuBarGap($0) }
                            ),
                            in: 0...8
                        ) {
                            Text("\(store.menuBarGap) space\(store.menuBarGap == 1 ? "" : "s")")
                                .font(AppFont.uiFont(size: 12))
                                .frame(minWidth: 55, alignment: .trailing)
                        }
                    }

                    HStack {
                        Text("Separator width")
                            .font(AppFont.uiFont(size: 12))
                        Spacer()
                        Stepper(
                            value: Binding(
                                get: { store.menuBarSeparatorWidth },
                                set: { store.setMenuBarSeparatorWidth($0) }
                            ),
                            in: 0...20
                        ) {
                            Text("\(store.menuBarSeparatorWidth) space\(store.menuBarSeparatorWidth == 1 ? "" : "s")")
                                .font(AppFont.uiFont(size: 12))
                                .frame(minWidth: 55, alignment: .trailing)
                        }
                    }
            }
        }
    }
}
