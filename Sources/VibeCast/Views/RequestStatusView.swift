import SwiftUI

struct RequestStatusView: View {
    @ObservedObject var store: VibeCastStore
    @State private var confirmsStopRecovery = false
    @State private var recoveryToStop: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.showsRequestProgress {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(store.progress).font(.callout).foregroundStyle(.secondary)
                }
                .accessibilityLabel(store.progress)
            } else if let error = store.latestError {
                Label {
                    Text(error).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                }
                .font(.system(size: 12))
            } else if let result = store.latestResult, result.source != .findPlaylist {
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.title).font(.system(size: 14, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = result.detail {
                        Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let url = result.playlist?.spotifyURL {
                        Link(destination: url) { Label("Open in Spotify", systemImage: "arrow.up.right") }
                            .font(.system(size: 12))
                    }
                }
            }
            if let notice = store.notificationNotice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
            if !store.isBusy, store.latestError != nil || store.notificationNotice != nil ||
                (store.latestResult != nil && store.latestResult?.source != .findPlaylist) {
                Button("Dismiss") { store.clear() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                    .help("Dismiss request feedback and keep your unfinished text")
                    .accessibilityLabel("Dismiss request feedback")
            }
            if let attempt = store.pendingPlaylistCreation, !store.isBusy {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recover \(attempt.name)").font(.callout)
                    Text("Check Spotify before making another playlist. This check won't create a duplicate.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Check Spotify") { store.recoverPlaylistCreation() }.buttonStyle(.borderedProminent)
                        stopRecoveryButton
                    }
                }
            }
            if let draft = store.unfinishedPlaylist, !store.isBusy {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(draft.playlist.name) is waiting for its songs.").font(.callout)
                    HStack {
                        Button("Finish playlist") { store.finishPlaylist() }.buttonStyle(.borderedProminent)
                        if let url = draft.playlist.spotifyURL { Link("Open in Spotify", destination: url) }
                    }
                    stopRecoveryButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog("Stop recovering this playlist?", isPresented: $confirmsStopRecovery, titleVisibility: .visible) {
            Button("Stop recovery", role: .destructive) {
                if let recoveryToStop { store.abandonPlaylistRecovery(id: recoveryToStop) }
                recoveryToStop = nil
            }
            Button("Keep recovery", role: .cancel) { }
        } message: {
            Text("This only stops VibeCast's recovery. It won't delete anything from Spotify. Check Spotify before trying again, because another request could create a duplicate playlist.")
        }
    }

    private var stopRecoveryButton: some View {
        Button("Stop recovery") {
            recoveryToStop = store.playlistRecoveryID
            confirmsStopRecovery = recoveryToStop != nil
        }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
    }
}
