import SwiftUI

/// Single-line label that truncates when it doesn't fit. If (and only if) it's
/// truncated, hovering shows the full text in a popover floating above the bar.
struct ArtistLabel: View {
    let text: String
    var font: Font = .subheadline
    var color: Color = .secondary

    @State private var fullWidth: CGFloat = 0
    @State private var overflowing = false
    @State private var showPopover = false
    @State private var hoverDelay: DispatchWorkItem?

    var body: some View {
        GeometryReader { geo in
            let container = geo.size.width

            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: container, alignment: .leading)
                // Measure the text's natural width to know if it's truncated.
                .background(
                    Text(text).font(font).lineLimit(1).fixedSize().hidden()
                        .background(GeometryReader { t in
                            Color.clear
                                .onAppear { fullWidth = t.size.width }
                                .onChange(of: text) { _, _ in fullWidth = t.size.width }
                        })
                )
                .onAppear { overflowing = fullWidth > container + 0.5 }
                .onChange(of: fullWidth) { _, _ in overflowing = fullWidth > container + 0.5 }
                .onChange(of: container) { _, _ in overflowing = fullWidth > container + 0.5 }
                .onHover { inside in
                    hoverDelay?.cancel()
                    guard inside, overflowing else { showPopover = false; return }
                    // Show only after the cursor has rested here for ~1s.
                    let work = DispatchWorkItem { showPopover = true }
                    hoverDelay = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
                }
                .popover(isPresented: $showPopover, arrowEdge: .top) {
                    Text(text)
                        .font(font)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .presentationCompactAdaptation(.popover)
                }
        }
        .frame(height: 18)
    }
}
