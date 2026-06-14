import SwiftUI

/// Scroll position/size snapshot read from a scroll view's geometry.
struct ScrollMetrics: Equatable {
    var offset: CGFloat = 0          // distance scrolled from the top
    var contentHeight: CGFloat = 0
    var visibleHeight: CGFloat = 0
}

/// Holds the live scroll metrics. It's a separate observable so per-frame scroll
/// updates re-render ONLY the scrollbar — not the list — which keeps native
/// 120 Hz/ProMotion scrolling smooth.
@MainActor
final class ScrollObserver: ObservableObject {
    @Published var metrics = ScrollMetrics()
}

/// A slim, rounded custom scrollbar that shows the current position and fades in
/// while scrolling, then quietly fades out — replaces the basic system scroller.
struct VerticalScrollbar: View {
    @ObservedObject var observer: ScrollObserver

    private var metrics: ScrollMetrics { observer.metrics }
    @State private var active = false
    @State private var fadeToken = 0

    private let width: CGFloat = 5
    private let minThumb: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            let track = geo.size.height
            let content = metrics.contentHeight
            let visible = metrics.visibleHeight

            if content > visible + 1 {
                let ratio = max(0, min(1, visible / content))
                let thumb = max(minThumb, track * ratio)
                let scrollable = max(1, content - visible)
                let y = (min(max(0, metrics.offset), scrollable) / scrollable) * (track - thumb)

                Capsule()
                    .fill(Color.primary.opacity(0.3))
                    .frame(width: width, height: thumb)
                    .offset(y: y)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 3)
                    .opacity(active ? 1 : 0)
                    .animation(.easeOut(duration: 0.25), value: active)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: metrics.offset) { _, _ in flash() }
    }

    private func flash() {
        active = true
        fadeToken += 1
        let token = fadeToken
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            if token == fadeToken { active = false }
        }
    }
}

extension View {
    /// Hides the system scroll indicators and overlays the custom scrollbar,
    /// driven by the scroll view's geometry. Metrics flow into a dedicated
    /// observable so only the scrollbar re-renders per frame (keeps 120 Hz).
    func customScrollbar(_ observer: ScrollObserver) -> some View {
        self
            .scrollIndicators(.never)
            .onScrollGeometryChange(for: ScrollMetrics.self) { geo in
                ScrollMetrics(
                    offset: geo.contentOffset.y + geo.contentInsets.top,
                    contentHeight: geo.contentSize.height,
                    visibleHeight: geo.containerSize.height
                )
            } action: { _, new in
                observer.metrics = new
            }
            .overlay { VerticalScrollbar(observer: observer) }
    }
}
