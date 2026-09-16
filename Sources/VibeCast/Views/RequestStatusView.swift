import SwiftUI

struct RequestStatusView: View {
    @ObservedObject var store: VibeCastStore

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
            if let draft = store.unfinishedPlaylist, !store.isBusy {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(draft.playlist.name) is waiting for its songs.").font(.callout)
                    HStack {
                        Button("Finish playlist") { store.finishPlaylist() }.buttonStyle(.borderedProminent)
                        if let url = draft.playlist.spotifyURL { Link("Open in Spotify", destination: url) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
