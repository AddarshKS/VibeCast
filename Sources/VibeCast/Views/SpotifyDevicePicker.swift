import SwiftUI

struct SpotifyDevicePicker: View {
    @Environment(\.playerDensity) private var density
    @ObservedObject var store: VibeCastStore
    @ObservedObject var details: PlayerDetailsStore
    var close: () -> Void
    @State private var retry = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Spotify devices").font(.system(size: density.value(15, 13), weight: .semibold))
                Spacer()
                PlayerIconButton(title: "Refresh devices", symbol: "arrow.clockwise") { retry += 1 }
                PlayerIconButton(title: "Close devices", symbol: "xmark", action: close)
            }
            switch details.devices {
            case .idle, .loading:
                ProgressView("Finding devices").controlSize(.small).font(.caption)
            case .failed(let error):
                Text(error).font(.caption).foregroundStyle(.secondary)
                Button("Try again") { retry += 1 }.buttonStyle(.bordered)
            case .loaded(let devices):
                if devices.isEmpty {
                    Text("Open Spotify on your Mac, phone or speaker to connect it.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(Array(devices.enumerated()), id: \.offset) { _, device in
                    Button { store.control(.transferToDevice(device)) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "hifispeaker").frame(width: 24)
                            Text(device.name).lineLimit(2)
                            Spacer()
                            if store.pendingPlayerAction == .transferToDevice(device) {
                                ProgressView().controlSize(.mini).frame(width: 16, height: 16)
                            } else if device.isRestricted == true || device.id == nil {
                                Image(systemName: "lock").foregroundStyle(.secondary)
                            } else if device.isActive {
                                Image(systemName: "checkmark").foregroundStyle(.teal)
                            }
                        }
                        .font(.system(size: 13)).padding(.vertical, density.value(10, 7))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isBusy || device.id == nil || device.isRestricted == true || device.isActive)
                    .accessibilityLabel(device.name + (device.isActive ? ", current device" : ""))
                    .help(device.isRestricted == true ? "Spotify does not allow controlling this device" : "Play on \(device.name)")
                }
            }
        }
        .task(id: "\(retry)-\(store.isBusy)") {
            guard !store.isBusy else { return }
            while !Task.isCancelled {
                await details.refreshDevices()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }
}
