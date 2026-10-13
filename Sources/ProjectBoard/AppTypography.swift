import SwiftUI

/// Shared project identity on Mac and iPhone, matching the website's layered motif.
/// Keep area folders and task/status symbols separate from project identity.
enum AppSymbols {
    static let project = "square.3.layers.3d"
}

/// Semantic system styles keep hierarchy consistent and support iPhone Dynamic Type.
/// Default Mac sizes: board 22, page 17, section/context 15, item/body 13, supporting 12, caption 11.
enum AppTypography {
    static let boardTitle: Font = .title.bold()
    static let pageTitle: Font = .title2.bold()
    static let profileInitial: Font = .title2.weight(.semibold)
    static let sectionTitle: Font = .title3.weight(.semibold)
    static let contextTitle: Font = .title3
    static let itemTitle: Font = .headline
    static let body: Font = .body
    static let supporting: Font = .callout
    static let caption: Font = .caption
    static let metadataEmphasis: Font = .caption.weight(.medium)

    #if os(iOS)
    static let workspaceTitle: Font = .title3.bold()
    static let sidebarAreaTitle: Font = .title2.weight(.semibold)
    static let sidebarAreaCount: Font = .body.weight(.medium)
    static let sidebarAreaIcon: Font = .title3.weight(.semibold)
    static let sidebarDisclosureIcon: Font = .callout.weight(.semibold)
    #else
    static let workspaceTitle: Font = .system(size: 24, weight: .bold)
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
    let headingColor: Color
    @ViewBuilder let content: () -> Content

    init(
        _ title: String,
        headingColor: Color = .primary,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.headingColor = headingColor
        self.content = content
    }

    var body: some View {
        Section {
            content()
        } header: {
            Text(title)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(headingColor)
                .textCase(nil)
        }
    }
}

/// The filled surface used by profile sections and task cards.
/// It follows the active System, Light, or Dark appearance without a separate border.
private struct AppCardSurface: ViewModifier {
    let cornerRadius: CGFloat

    private var background: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    private var adaptiveLift: Color {
        #if os(iOS)
        Color.clear
        #else
        Color.primary.opacity(0.04)
        #endif
    }

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(background)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(adaptiveLift)
                }
        }
    }
}

extension View {
    func appCardSurface(cornerRadius: CGFloat = 18) -> some View {
        modifier(AppCardSurface(cornerRadius: cornerRadius))
    }
}

enum AppGlassButtonSize: Equatable {
    case small, medium, large, extraLarge

    var dimension: CGFloat {
        switch self {
        case .small: 32
        case .medium: 40
        case .large: 52
        case .extraLarge: 68
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small: 12
        case .medium: 16
        case .large: 20
        case .extraLarge: 24
        }
    }

    /// Optical space between a circular button's symbol and its outer edge.
    /// The symbol size is derived from this value so callers never tune icons individually.
    var circularContentInset: CGFloat {
        switch self {
        case .small: 8
        case .medium: 12
        case .large: 13
        case .extraLarge: 17
        }
    }

    var iconDimension: CGFloat {
        dimension - (circularContentInset * 2)
    }

    var cornerRadius: CGFloat {
        switch self {
        case .small: 10
        case .medium: 12
        case .large: 16
        case .extraLarge: 18
        }
    }

    var font: Font {
        switch self {
        case .small: AppTypography.supporting.weight(.semibold)
        case .medium: AppTypography.body.weight(.semibold)
        case .large: AppTypography.itemTitle
        case .extraLarge: AppTypography.sectionTitle
        }
    }

    var iconFont: Font {
        .system(size: iconDimension, weight: self == .small ? .semibold : .medium)
    }

}

enum AppGlassButtonShape: Equatable {
    case icon, circle, square, rectangle
}

private struct AppGlassButtonStyle: ButtonStyle {
    let size: AppGlassButtonSize
    let shape: AppGlassButtonShape
    let accent: Bool

    func makeBody(configuration: Configuration) -> some View {
        AppGlassButtonStyleBody(
            label: configuration.label,
            size: size,
            shape: shape,
            accent: accent,
            isPressed: configuration.isPressed
        )
    }
}

private struct AppGlassButtonStyleBody<Label: View>: View {
    let label: Label
    let size: AppGlassButtonSize
    let shape: AppGlassButtonShape
    let accent: Bool
    let isPressed: Bool

    @ViewBuilder
    var body: some View {
        if shape == .icon {
            iconLabel
        } else if #available(macOS 26.0, iOS 26.0, *) {
            glassLabel
        } else {
            fallbackLabel
        }
    }

    private var iconLabel: some View {
        label
            .font(size.iconFont)
            .foregroundStyle(Color.accentColor)
            .frame(width: size.dimension, height: size.dimension)
            .contentShape(Rectangle())
            .opacity(isPressed ? 0.65 : 1)
    }

    @available(macOS 26.0, iOS 26.0, *)
    @ViewBuilder
    private var glassLabel: some View {
        let glass = Glass.regular.interactive()
        switch shape {
        case .icon:
            iconLabel
        case .circle:
            label
                .font(size.iconFont)
                .foregroundStyle(Color.accentColor)
                .frame(width: size.dimension, height: size.dimension)
                .contentShape(Circle())
                .glassEffect(glass, in: .circle)
                .opacity(isPressed ? 0.72 : 1)
        case .square:
            label
                .font(size.font)
                .foregroundStyle(Color.accentColor)
                .frame(width: size.dimension, height: size.dimension)
                .contentShape(RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
                .glassEffect(glass, in: .rect(cornerRadius: size.cornerRadius))
                .opacity(isPressed ? 0.72 : 1)
        case .rectangle:
            label
                .font(size.font)
                .foregroundStyle(Color.accentColor)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, size.horizontalPadding)
                .frame(minHeight: size.dimension)
                .contentShape(RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
                .glassEffect(glass, in: .rect(cornerRadius: size.cornerRadius))
                .opacity(isPressed ? 0.72 : 1)
        }
    }

    @ViewBuilder
    private var fallbackLabel: some View {
        switch shape {
        case .icon:
            iconLabel
        case .circle:
            label
                .font(size.iconFont)
                .foregroundStyle(accent ? Color.accentColor : Color.primary)
                .frame(width: size.dimension, height: size.dimension)
                .contentShape(Circle())
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                .opacity(isPressed ? 0.65 : 1)
        case .square:
            label
                .font(size.font)
                .foregroundStyle(accent ? Color.accentColor : Color.primary)
                .frame(width: size.dimension, height: size.dimension)
                .contentShape(RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                .opacity(isPressed ? 0.65 : 1)
        case .rectangle:
            label
                .font(size.font)
                .foregroundStyle(accent ? Color.accentColor : Color.primary)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, size.horizontalPadding)
                .frame(minHeight: size.dimension)
                .contentShape(RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                .opacity(isPressed ? 0.65 : 1)
        }
    }
}

extension View {
    /// A reproducible Liquid Glass theme whose entire visible surface is the hit target.
    @ViewBuilder
    func appGlassButton(
        size: AppGlassButtonSize = .medium,
        shape: AppGlassButtonShape = .rectangle,
        accent: Bool = false
    ) -> some View {
        self.buttonStyle(AppGlassButtonStyle(size: size, shape: shape, accent: accent))
    }
}

enum AppGlassActionSymbol {
    case back
    case cancel
    case confirm

    var systemName: String {
        switch self {
        case .back: "chevron.left"
        case .cancel: "xmark"
        case .confirm: "checkmark"
        }
    }
}

struct AppActionGlyph: View {
    let symbol: AppGlassActionSymbol
    var size: AppGlassButtonSize = .medium

    var body: some View {
        Image(systemName: symbol.systemName)
            .font(size.iconFont)
            .frame(width: size.iconDimension, height: size.iconDimension)
    }
}

/// A standard back, X, or checkmark action whose glyph and surface use the same size preset.
/// Keeping both values here prevents individual menus from overriding the symbol size.
struct AppGlassActionButton: View {
    let symbol: AppGlassActionSymbol
    let accessibilityLabel: String
    var size: AppGlassButtonSize = .medium
    var accent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AppActionGlyph(symbol: symbol, size: size)
        }
        .appGlassButton(size: size, shape: .circle, accent: accent)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct EditorToolbarActions: ToolbarContent {
    let confirmationTitle: String
    let canConfirm: Bool
    let cancel: () -> Void
    let confirm: () -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .cancellationAction) { cancelButton }
                .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .confirmationAction) { confirmationButton }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .cancellationAction) { cancelButton }
            ToolbarItem(placement: .confirmationAction) { confirmationButton }
        }
        #else
        ToolbarItem(placement: .cancellationAction) { cancelButton }
        ToolbarItem(placement: .confirmationAction) { confirmationButton }
        #endif
    }

    private var cancelButton: some View {
        AppGlassActionButton(symbol: .cancel, accessibilityLabel: "Cancel", action: cancel)
    }

    @ViewBuilder
    private var confirmationButton: some View {
        AppGlassActionButton(
            symbol: .confirm,
            accessibilityLabel: confirmationTitle,
            accent: true,
            action: confirm
        )
            .disabled(!canConfirm)
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

/// Shared identity label for workspace controls and profile cards on both platforms.
struct ProfileInitial: View {
    let displayName: String?

    private var initial: String {
        guard let character = displayName?.first(where: { $0.isLetter || $0.isNumber }) else { return "?" }
        return String(String(character).uppercased().prefix(1))
    }

    var body: some View {
        Text(initial)
            .font(AppTypography.profileInitial)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityHidden(true)
    }
}
