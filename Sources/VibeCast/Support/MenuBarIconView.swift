import SwiftUI

struct MenuBarIconView: View {
    var body: some View {
        Image(systemName: "music.note.list")
            .font(.system(size: 14, weight: .medium))
            .frame(width: 18, height: 18)
    }
}
