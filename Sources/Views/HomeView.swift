import SwiftUI

/// The Home destination: a vertical feed of shelves.
struct HomeView: View {
    @EnvironmentObject var home: HomeFeedModel
    @State private var scrollObserver = ScrollObserver()
    var topInset: CGFloat = 0

    var body: some View {
        Group {
            if home.shelves.isEmpty {
                if home.isLoading {
                    skeleton
                } else {
                    ContentUnavailableView("Главная пуста",
                                           systemImage: "square.stack",
                                           description: Text("Послушайте музыку — здесь появятся подборки."))
                }
            } else {
                feed
            }
        }
        .task { await home.load() }
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(home.shelves) { shelf in
                    ShelfRow(shelf: shelf)
                }
            }
            .padding(.vertical, 16)
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.top, topInset, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .customScrollbar(scrollObserver)
    }

    // Lightweight placeholder while the network shelves load.
    private var skeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                            .frame(width: 160, height: 18).padding(.horizontal, 16)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(0..<5, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(.quaternary)
                                        .frame(width: 148, height: 188)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .disabled(true)
                    }
                }
            }
            .padding(.vertical, 16)
            .redacted(reason: .placeholder)
        }
    }
}
