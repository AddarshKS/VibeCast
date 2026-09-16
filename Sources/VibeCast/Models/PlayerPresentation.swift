import Combine
import Foundation

@MainActor
final class PlayerPresentation: ObservableObject {
    @Published var isDetached = false
    @Published var maximumHeight: CGFloat = 680
}
