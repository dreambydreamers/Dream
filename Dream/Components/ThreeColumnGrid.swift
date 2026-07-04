import SwiftUI

struct ThreeColumnGrid<Content: View>: View {
    var spacing: CGFloat = 2
    @ViewBuilder var content: () -> Content

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: 3),
            spacing: spacing
        ) {
            content()
        }
    }
}
