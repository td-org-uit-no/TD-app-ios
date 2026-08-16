import SwiftUI
import UIKit

/// The website's design tokens, ported from the frontend's
/// `src/styles/colors.scss` so the app matches td-uit.no exactly.
enum TD {

    // MARK: - Colors (verbatim from colors.scss)

    /// TD red. The site's Chakra theme (`src/theme.ts`, `red.td`) uses
    /// `#C7323A`, which supersedes the older `$td-red: #a4161a` in colors.scss.
    static let red = Color(hex: 0xC7323A)
    /// `$secondary: #f8d2cc`
    static let secondary = Color(hex: 0xF8D2CC)

    /// `$background-color: #161926`
    static let background = Color(hex: 0x161926)
    /// `$off-background-color: #161a1d`
    static let offBackground = Color(hex: 0x161A1D)

    /// The event card background from `horizontal.scss` (`#2b2c3d`).
    static let surface = Color(hex: 0x2B2C3D)

    /// `$active-label-color: #7e4ccb` — the purple used for focus/active state.
    static let activeLabel = Color(hex: 0x7E4CCB)
    /// `$inactive-label-color: #b3b3b3`
    static let inactiveLabel = Color(hex: 0xB3B3B3)

    /// `$input-background: #272530`, `$input-border: #2f2c45`
    static let inputBackground = Color(hex: 0x272530)
    static let inputBorder = Color(hex: 0x2F2C45)

    /// `$off-primary: #444658`, `$primary: #ffffff`
    static let offPrimary = Color(hex: 0x444658)
    static let primary = Color.white

    static let success = Color(hex: 0x5CB85C)
    static let error = Color(hex: 0xD9534F)
    static let info = Color(hex: 0x5BC0DE)
    static let warning = Color(hex: 0xF0AD4E)

    /// Card text colors from `horizontal.scss`.
    static let cardTitle = Color(hex: 0xCCCCCC)
    static let cardSubtitle = Color(hex: 0xA9A9A9)

    /// The orange used for job tags in `jobCard.module.scss`.
    static let tagOrange = Color(red: 240 / 255, green: 150 / 255, blue: 103 / 255)

    // MARK: - Typography
    //
    // The site loads Inter (index.html) and uses an 18px base with a 1.333
    // modular scale (typography.scss). iOS has no Inter, so we use the system
    // font, which is metric-similar enough to read the same. Sizes below follow
    // the site's scale, scaled down for a phone.

    enum Font {
        static func title() -> SwiftUI.Font { .system(size: 28, weight: .semibold) }
        static func heading() -> SwiftUI.Font { .system(size: 22, weight: .semibold) }
        static func cardTitle() -> SwiftUI.Font { .system(size: 19, weight: .semibold) }
        static func body() -> SwiftUI.Font { .system(size: 16, weight: .regular) }
        static func subtitle() -> SwiftUI.Font { .system(size: 14, weight: .light) }
        static func small() -> SwiftUI.Font { .system(size: 12, weight: .regular) }
        static func tag() -> SwiftUI.Font { .system(size: 11, weight: .medium) }
    }

    // MARK: - Assets
    //
    // Image assets lifted from the website. `logo` and `fullLogo` are TD red on
    // transparent, so they sit directly on the dark background; `logoBlue` is
    // the dark-navy variant meant for light surfaces.

    enum Asset {
        /// Square "D" mark.
        static let logo = "td-logo"
        /// Dark-navy square mark — for light backgrounds only.
        static let logoBlue = "td-logo-blue"
        /// Wide "TROMSØ …" wordmark.
        static let fullLogo = "td-full-logo"
        /// Red chevron used as a menu/disclosure glyph.
        static let menuIcon = "menu-icon"
        static let tdBytesQR = "tdbytes-qr"
        static let tdBytesLocation = "tdbytes-location"
        static let discordInvite = "IFI-discord-invite"
    }

    // MARK: - Metrics

    enum Radius {
        /// Cards use `0.5rem`; inputs use `5px`.
        static let card: CGFloat = 8
        static let input: CGFloat = 5
        static let image: CGFloat = 8
    }

    /// Shared list-card metrics. Both `JobCard` and `EventRow` read these, so
    /// the two lists cannot drift apart the way they had.
    enum Card {
        /// Inset from the card's edge to its content.
        static let padding: CGFloat = 14
        /// Gap between a card's stacked sections.
        static let spacing: CGFloat = 8
        /// Gap between a title and the subtitle beneath it.
        static let titleGap: CGFloat = 4
        /// Gap between tag pills.
        static let tagGap: CGFloat = 5
        /// Artwork size — one value, so a logo and a poster match.
        static let thumbnail: CGFloat = 56
        /// Fixed row heights. See `TDCard.height` for why these are fixed
        /// rather than minimums.
        static let jobHeight: CGFloat = 186
        static let eventHeight: CGFloat = 104
    }
}

extension Color {
    /// Builds a color from a `0xRRGGBB` literal so the SCSS hex values can be
    /// transcribed directly.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Reusable components

/// The site's card surface: `#2b2c3d`, 0.5rem radius, soft drop shadow.
///
/// `height` pins the card's frame rather than letting content size it. A card
/// whose frame follows its content paints a surface of a different height per
/// row — a title wrapping to two lines, a description filling three, a listing
/// with no tags — and because the surface *is* the frame, the constant spacing
/// between frames reads as uneven space between the visible rectangles. Pinning
/// the height makes painted size and frame size agree, so one `spacing:` value
/// renders as one gap.
struct TDCard<Content: View>: View {
    var height: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(height: height)
            // The shadow belongs to the card's shape, not to the card.
            //
            // `.shadow()` applied to the whole view inherits down into every
            // child, so each `Text`, tag pill and SF Symbol inside the card was
            // given a drop shadow of its own — a dozen separately blurred
            // offscreen layers per card, recomposited every frame while
            // scrolling. Shadowing the background shape instead blurs exactly
            // one opaque rounded rectangle, and the content draws flat on top.
            // Visually identical: the text sat on an opaque surface, so its
            // shadows were never actually visible.
            .background {
                RoundedRectangle(cornerRadius: TD.Radius.card)
                    .fill(TD.surface)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            }
    }
}

/// A pill tag, matching the job card's translucent-orange treatment.
struct TDTag: View {
    let text: String
    var icon: String?
    var color: Color = TD.tagOrange

    var body: some View {
        HStack(spacing: 3) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(TD.Font.tag())
        .foregroundStyle(TD.primary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.3), in: RoundedRectangle(cornerRadius: TD.Radius.input))
    }
}

/// Buttons as the website styles them (`src/theme.ts`).
///
/// Chakra's base style is an outlined button — `border: 1px solid`,
/// `text-transform: uppercase`, `font-weight: 700` — with two variants:
///
/// - `primary`: white text, `slate.500` border, fills with `slate.500` on hover
/// - `secondary`: `secondary` (#f8d2cc) text and border, inverting to dark text
///   on a `secondary` background on hover
///
/// Touch has no hover, so the hover fill is used as the *pressed* state.
struct TDButtonStyle: ButtonStyle {
    enum Variant {
        case primary
        case secondary
    }

    var variant: Variant = .secondary
    /// Set false for buttons that should hug their content.
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed

        return configuration.label
            // uppercase + 700 weight, per the Chakra baseStyle.
            .textCase(.uppercase)
            .font(TD.Font.body().weight(.bold))
            .foregroundStyle(foreground(pressed: pressed))
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                (pressed ? fill : .clear),
                in: RoundedRectangle(cornerRadius: TD.Radius.input)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TD.Radius.input)
                    .strokeBorder(border, lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.15), value: pressed)
    }

    private func foreground(pressed: Bool) -> Color {
        switch variant {
        case .primary:
            TD.primary
        case .secondary:
            // Hover/press inverts to dark text on the light fill.
            pressed ? TD.background : TD.secondary
        }
    }

    private var border: Color {
        switch variant {
        case .primary: TD.offPrimary   // slate.500
        case .secondary: TD.secondary
        }
    }

    private var fill: Color {
        switch variant {
        case .primary: TD.offPrimary
        case .secondary: TD.secondary
        }
    }
}

/// The page header every screen wears: the TD mark, the page's name, and
/// optional trailing controls.
///
/// The navigation bar is hidden on the screens that use this and the header is
/// drawn as ordinary content instead, so the top of the page is one continuous
/// `TD.background` rather than a bar in a second surface colour.
///
/// Pushed screens pass a `back` action, which draws a chevron ahead of the logo
/// in place of the system back button they gave up when hiding the bar.
struct TDPageHeader<Trailing: View>: View {
    let title: String
    var back: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    init(
        _ title: String,
        back: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.back = back
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            if let back {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(TD.red)
                        // A wide-enough target that the chevron itself doesn't
                        // have to be finger-sized.
                        .frame(width: 24, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tilbake")
            }

            Image(TD.Asset.logo)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)

            Text(title)
                .font(TD.Font.title())
                .foregroundStyle(TD.primary)
                // Long titles (an event's name on the detail page) shrink
                // rather than wrap, so the header keeps one constant height
                // across every screen.
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer(minLength: 8)

            trailing
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }
}

/// The site's dark page background, behind a screen's content.
///
/// Screens compose this as `ZStack { TDScreenBackground(); … }` rather than as
/// a `.background` modifier: the content above it is a `VStack` of a header and
/// a scroll view, and the background has to span the full screen including the
/// safe areas the scroll view stops short of.
struct TDScreenBackground: View {
    var body: some View {
        TD.background.ignoresSafeArea()
    }
}

/// The tappable row shown inside a `PhotosPicker`, previewing the chosen image
/// and offering a clear button.
///
/// This exists as a view rather than as the picker's label closure directly
/// because `PhotosPicker`'s label parameter is declared `@Sendable` and carries
/// no actor. Under this target's default `MainActor` isolation, reading a
/// `TD.*` token or a `@State` value straight from that closure is a data-race
/// warning in Swift 6. `View.body` *is* main-actor isolated, so moving the
/// design tokens in here makes the isolation correct rather than suppressed —
/// the closure is left doing nothing but calling this initialiser.
///
/// `selection` is a `Binding` (which is `Sendable`) instead of a value plus a
/// mutating callback, so the clear button mutates the caller's `@State` from
/// inside this isolated `body`.
struct TDImagePickerLabel: View {
    /// The image bytes to preview, cleared in place by the clear button.
    @Binding var data: Data?
    /// Shown when nothing is selected yet.
    let placeholderIcon: String
    let emptyTitle: String
    let selectedTitle: String
    /// Posters are cropped to fill; logos are fitted so they aren't cut off.
    let contentMode: ContentMode
    /// Cleared alongside `data` so the picker can re-offer the same photo.
    let onClear: @MainActor () -> Void

    /// Explicitly `nonisolated` so the `@Sendable` picker label closure can
    /// construct this. The synthesised memberwise initialiser would inherit the
    /// file's default `MainActor` isolation and warn at every call site.
    nonisolated init(
        data: Binding<Data?>,
        placeholderIcon: String,
        emptyTitle: String,
        selectedTitle: String,
        contentMode: ContentMode = .fill,
        onClear: @escaping @MainActor () -> Void = {}
    ) {
        _data = data
        self.placeholderIcon = placeholderIcon
        self.emptyTitle = emptyTitle
        self.selectedTitle = selectedTitle
        self.contentMode = contentMode
        self.onClear = onClear
    }

    var body: some View {
        HStack(spacing: 10) {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: placeholderIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(TD.inactiveLabel)
                    .frame(width: 44, height: 44)
                    .background(
                        TD.surface,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }

            Text(data == nil ? emptyTitle : selectedTitle)
                .font(TD.Font.body())
                .foregroundStyle(data == nil ? TD.secondary : TD.primary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            if data != nil {
                Button {
                    data = nil
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(TD.inactiveLabel)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            TD.inputBackground,
            in: RoundedRectangle(cornerRadius: TD.Radius.input)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TD.Radius.input)
                .strokeBorder(TD.inputBorder, lineWidth: 2)
        )
    }
}
