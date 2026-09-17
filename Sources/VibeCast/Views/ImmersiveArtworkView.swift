import SwiftUI

struct ImmersiveArtworkView: View {
    let url: URL?
    let size: CGFloat
    var reading = false
    var height: CGFloat? = nil

    var body: some View {
        PlayerArtwork(url: url) { image in
            artwork(image)
                .blur(radius: reading ? 14 : 0, opaque: true)
                .scaleEffect(reading ? 1.12 : 1)
                .overlay {
                    if reading {
                        Color.black.opacity(0.62)
                        LinearGradient(colors: [.black.opacity(0.2), .clear], startPoint: .leading, endPoint: .trailing)
                    } else {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.03), location: 0.22),
                            .init(color: .black.opacity(0.40), location: 0.44),
                            .init(color: .black.opacity(0.66), location: 0.68),
                            .init(color: .black.opacity(0.76), location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                    }
                }
        }
        .frame(width: size, height: height ?? size).clipped()
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    @ViewBuilder private func artwork(_ image: Image?) -> some View {
        if let image {
            image.resizable().scaledToFill().frame(width: size, height: height ?? size).clipped()
        } else {
            ZStack {
                Color(white: 0.13)
                Image(systemName: "waveform").font(.system(size: size * 0.28, weight: .light)).foregroundStyle(.teal)
            }
            .frame(width: size, height: height ?? size)
        }
    }
}
