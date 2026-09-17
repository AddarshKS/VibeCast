import SwiftUI

struct MenuBarIconView: View {
    var body: some View {
        Image(nsImage: ResourceImage.menuBarSymbol)
            .resizable().scaledToFit()
            .frame(width: 20, height: 18)
    }
}
