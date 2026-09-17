import SwiftUI

struct MiniplayerView: View {
    @ObservedObject var store: VibeCastStore
    @ObservedObject var presentation: PlayerPresentation
    var toggleMiniplayer: () -> Void
    var toggleWindow: () -> Void
    var toggleDetail: (PlayerPanel) -> Void
    var detailTransition: AnyTransition = .opacity
    var selectPanel: (PlayerPanel?) -> Void

    var body: some View {
        ZStack {
            if let panel = presentation.miniplayerPanel {
                MiniplayerDetailsView(store: store, presentation: presentation, panel: panel,
                                      close: { toggleDetail(panel) }, toggleWindow: toggleWindow)
                    .id(panel)
                    .transition(detailTransition).zIndex(1)
            } else {
                ImmersiveMiniplayerView(store: store, presentation: presentation,
                    toggleMiniplayer: toggleMiniplayer, toggleWindow: toggleWindow,
                    selectPanel: selectMiniplayerPanel)
                    .transition(detailTransition).zIndex(0)
            }
        }
    }

    private func selectMiniplayerPanel(_ panel: PlayerPanel?) {
        if let panel, panel == .lyrics || panel == .queue { toggleDetail(panel) }
        else { selectPanel(panel) }
    }
}
