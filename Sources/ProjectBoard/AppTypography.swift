import SwiftUI

/// Semantic system styles keep hierarchy consistent and support iPhone Dynamic Type.
/// Default Mac sizes: page 17, section/context 15, item/body 13, supporting 12, caption 11.
enum AppTypography {
    static let pageTitle: Font = .title2.bold()
    static let sectionTitle: Font = .title3.weight(.semibold)
    static let contextTitle: Font = .title3
    static let itemTitle: Font = .headline
    static let body: Font = .body
    static let supporting: Font = .callout
    static let caption: Font = .caption
    static let metadataEmphasis: Font = .caption.weight(.medium)

    // Symbol sizes are independent of the text hierarchy.
    static let controlIcon: Font = .system(size: 22)
    static let smallIcon: Font = .caption.weight(.semibold)
}

/// Use the same section heading in every grouped form.
struct AppSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        Section {
            content()
        } header: {
            Text(title).font(AppTypography.sectionTitle).textCase(nil)
        }
    }
}
