import Foundation

/// A horizontal row ("polka") on the Home feed.
struct Shelf: Identifiable, Hashable {
    enum Style: Hashable { case carousel }

    let id: String
    let title: String
    var style: Style = .carousel
    var items: [Track]
    /// When set, the header shows a tappable "see all" affordance.
    var actionTitle: String? = nil

    init(id: String = UUID().uuidString,
         title: String,
         style: Style = .carousel,
         items: [Track],
         actionTitle: String? = nil) {
        self.id = id
        self.title = title
        self.style = style
        self.items = items
        self.actionTitle = actionTitle
    }
}
