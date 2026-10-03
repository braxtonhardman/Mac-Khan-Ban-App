import SwiftUI

/// Semantic system styles keep hierarchy consistent and support iPhone Dynamic Type.
/// Default Mac sizes: board 22, page 17, section/context 15, item/body 13, supporting 12, caption 11.
enum AppTypography {
    static let boardTitle: Font = .title.bold()
    static let pageTitle: Font = .title2.bold()
    static let sectionTitle: Font = .title3.weight(.semibold)
    static let contextTitle: Font = .title3
    static let itemTitle: Font = .headline
    static let body: Font = .body
    static let supporting: Font = .callout
    static let caption: Font = .caption
    static let metadataEmphasis: Font = .caption.weight(.medium)

    #if os(iOS)
    static let sidebarAreaTitle: Font = .title2.weight(.semibold)
    static let sidebarAreaIcon: Font = .title3.weight(.semibold)
    static let sidebarDisclosureIcon: Font = .callout.weight(.semibold)
    #else
    static let sidebarAreaTitle: Font = sectionTitle
    static let sidebarAreaIcon: Font = itemTitle
    static let sidebarDisclosureIcon: Font = smallIcon
    #endif

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

enum AppGlassButtonSize {
    case small, medium, large

    var dimension: CGFloat {
        switch self {
        case .small: 32
        case .medium: 40
        case .large: 52
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small: 12
        case .medium: 16
        case .large: 20
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .small: 10
        case .medium: 12
        case .large: 16
        }
    }

    var font: Font {
        switch self {
        case .small: AppTypography.caption.weight(.semibold)
        case .medium: AppTypography.body.weight(.semibold)
        case .large: AppTypography.itemTitle
        }
    }

    var iconFont: Font {
        switch self {
        case .small: .system(size: 17, weight: .semibold)
        case .medium: .system(size: 22, weight: .medium)
        case .large: .system(size: 26, weight: .medium)
        }
    }
}

enum AppGlassButtonShape: Equatable {
    case icon, circle, square, rectangle
}

extension View {
    /// A reproducible Liquid Glass theme with explicit size and shape variants.
    @ViewBuilder
    func appGlassButton(
        size: AppGlassButtonSize = .medium,
        shape: AppGlassButtonShape = .rectangle,
        accent: Bool = false
    ) -> some View {
        if shape == .icon {
            self.buttonStyle(.plain)
                .font(size.iconFont)
                .foregroundStyle(Color.accentColor)
                .frame(width: size.dimension, height: size.dimension)
                .contentShape(Rectangle())
        } else if #available(macOS 26.0, iOS 26.0, *) {
            let glass = (accent ? Glass.regular.tint(Color.accentColor.opacity(0.35)) : Glass.regular).interactive()
            switch shape {
            case .icon:
                EmptyView()
            case .circle:
                self.buttonStyle(.plain)
                    .font(size.font)
                    .foregroundStyle(Color.primary)
                    .frame(width: size.dimension, height: size.dimension)
                    .glassEffect(glass, in: .circle)
            case .square:
                self.buttonStyle(.plain)
                    .font(size.font)
                    .foregroundStyle(Color.primary)
                    .frame(width: size.dimension, height: size.dimension)
                    .glassEffect(glass, in: .rect(cornerRadius: size.cornerRadius))
            case .rectangle:
                self.buttonStyle(.plain)
                    .font(size.font)
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, size.horizontalPadding)
                    .frame(minHeight: size.dimension)
                    .glassEffect(glass, in: .rect(cornerRadius: size.cornerRadius))
            }
        } else {
            switch shape {
            case .icon:
                EmptyView()
            case .circle, .square:
                self.buttonStyle(.bordered)
                    .frame(width: size.dimension, height: size.dimension)
                    .tint(accent ? Color.accentColor : nil)
            case .rectangle:
                self.buttonStyle(.bordered)
                    .frame(minHeight: size.dimension)
                    .tint(accent ? Color.accentColor : nil)
            }
        }
    }
}

struct EditorToolbarActions: ToolbarContent {
    let confirmationTitle: String
    let canConfirm: Bool
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: cancel) {
                Image(systemName: "xmark")
            }
            .appGlassButton(shape: .circle)
            .accessibilityLabel("Cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(confirmationTitle, action: confirm)
                .appGlassButton(accent: true)
                .disabled(!canConfirm)
        }
    }
}

struct WorkspaceEditorCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
        }
    }
}
