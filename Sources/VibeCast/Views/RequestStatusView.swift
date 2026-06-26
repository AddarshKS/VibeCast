import SwiftUI

struct RequestStatusView: View {
    @ObservedObject var store: VibeCastStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.requestState.displayText, systemImage: iconName)
                .font(.subheadline)
                .foregroundStyle(foregroundStyle)

            if let result = store.latestResult {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.callout.weight(.semibold))
                    if let detail = result.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let error = store.latestError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var iconName: String {
        switch store.requestState {
        case .idle: "sparkles"
        case .routing: "arrow.triangle.branch"
        case .executing: "waveform"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var foregroundStyle: some ShapeStyle {
        switch store.requestState {
        case .failed:
            return AnyShapeStyle(.red)
        case .completed:
            return AnyShapeStyle(.green)
        default:
            return AnyShapeStyle(.primary)
        }
    }
}
