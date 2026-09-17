import SwiftUI

struct SettingsFirstClick: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 15.0, *) { content.allowsWindowActivationEvents(true) }
        else { content }
    }
}

struct SettingsGlass: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.background {
                RoundedRectangle(cornerRadius: 8).fill(.clear)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
            }
        } else {
            content.background(.regularMaterial)
        }
    }
}
