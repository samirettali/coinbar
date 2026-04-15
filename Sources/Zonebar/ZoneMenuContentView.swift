import AppKit
import SwiftUI

struct ZoneMenuContentView: View {
    @ObservedObject var store: TimeZoneStore
    @State private var isEditingZones = false
    @State private var zonesDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(store.zones) { zone in
                ZoneRowView(
                    zone: zone,
                    time: store.timeText(for: zone.identifier),
                    date: store.dateText(for: zone.identifier),
                    offset: store.offsetText(for: zone.identifier),
                    isVisibleInMenuBar: store.showsInMenuBar(zone.identifier),
                    onVisibilityChange: { isVisible in
                        store.setMenuBarVisibility(for: zone.identifier, isVisible: isVisible)
                    }
                )
            }

            Divider()

            if isEditingZones {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tracked Timezones")
                        .font(AppFont.uiFont(size: 12, weight: .semibold))

                    Text("One IANA timezone per line")
                        .font(AppFont.uiFont(size: 11))
                        .foregroundStyle(.secondary)

                    TextEditor(text: $zonesDraft)
                        .font(AppFont.uiFont(size: 12))
                        .frame(height: 100)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2))
                        }

                    HStack {
                        Button("Cancel") {
                            isEditingZones = false
                            zonesDraft = store.editableZonesText()
                        }

                        Spacer()

                        Button("Save") {
                            store.updateZones(from: zonesDraft)
                            zonesDraft = store.editableZonesText()
                            isEditingZones = false
                        }
                    }
                }

                Divider()
            }

            HStack {
                Button(isEditingZones ? "Editing..." : "Timezones") {
                    zonesDraft = store.editableZonesText()
                    isEditingZones.toggle()
                }
                .disabled(isEditingZones)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 280)
        .onAppear {
            zonesDraft = store.editableZonesText()
        }
    }
}

private struct ZoneRowView: View {
    let zone: TrackedTimeZone
    let time: String
    let date: String
    let offset: String
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
                Text(zone.displayName)
                    .font(AppFont.uiFont(size: 13, weight: .semibold))

                Text("\(zone.identifier)  \(offset)")
                    .font(AppFont.uiFont(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(time)
                    .font(AppFont.uiFont(size: 15, weight: .medium))

                Text(date)
                    .font(AppFont.uiFont(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
