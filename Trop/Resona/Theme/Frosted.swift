//
//  Frosted.swift
//  Resona
//
//  Flat, matte frosted-glass surfaces (Android-17 style blur) — explicitly
//  NOT Liquid Glass: no refraction, no specular highlights, no glassEffect.
//
//  Two tools:
//  • FrostedSurface — live background blur (system material, rendered in the
//    classic matte style because the app opts out of Liquid Glass) with a
//    Material 3 / artwork tint on top. For chrome that floats over moving
//    content (mini player, navigation bar, sheets, menus).
//  • BlurredArtwork — a cover blurred ONCE in the background with Core Image
//    and cached. Drawing it is as cheap as drawing any image, so cards and
//    the player background don't recompute a Gaussian blur every frame
//    while scrolling or animating.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

// MARK: - Tokens

/// One set of rules for every blur in the app (Android-17 style frosted
/// glass): thin material, light tint, hairline edge, a bit more saturation.
enum M3Frost {
    enum Role {
        /// Content cards (Keep listening, library) — most see-through.
        case card
        /// Floating chrome over content (mini player, dropdown, dialogs).
        case floating
        /// Bars the user reads text on (navigation bar, top bars).
        case chrome
        /// Sheets with long content (menus, queue).
        case sheet
    }

    static let material: Material = .ultraThinMaterial

    /// Tint over the blur: 20–35 % so the content behind stays visible.
    static func tintOpacity(_ role: Role) -> Double {
        switch role {
        case .card: 0.22
        case .floating: 0.26
        case .chrome: 0.32
        case .sheet: 0.35
        }
    }

    /// 1 px light edge on floating shapes.
    static let edgeOpacity = 0.14
    static let edgeWidth: CGFloat = 1
    /// Saturation boost of what shows through.
    static let saturation = 1.3
    /// Pre-blurred artwork (Core Image) radius, in 96 px space.
    static let artworkBlurRadius = 12.0
    /// How strongly a card's own blurred cover shows.
    static let artworkOpacity = 0.85

    static func showsEdge(_ role: Role) -> Bool {
        switch role {
        case .card, .floating: true
        case .chrome, .sheet: false
        }
    }
}

// MARK: - Live frosted surface

struct FrostedSurface<S: Shape, T: ShapeStyle>: View {
    var shape: S
    /// Tint laid over the blur (surface colour, artwork colour/gradient).
    var tint: T
    var role: M3Frost.Role = .floating
    /// Override the role's hairline edge (e.g. when the caller strokes its
    /// own, differently shaped outline).
    var edge: Bool?

    var body: some View {
        ZStack {
            shape.fill(M3Frost.material)
                .saturation(M3Frost.saturation)
            shape.fill(tint).opacity(M3Frost.tintOpacity(role))
            if edge ?? M3Frost.showsEdge(role) {
                shape.stroke(.white.opacity(M3Frost.edgeOpacity), lineWidth: M3Frost.edgeWidth)
            }
        }
        .environment(\.colorScheme, .dark)
        .compositingGroup()
    }
}

extension FrostedSurface where S == Rectangle {
    init(tint: T, role: M3Frost.Role = .floating, edge: Bool? = nil) {
        self.init(shape: Rectangle(), tint: tint, role: role, edge: edge)
    }
}

/// Card background: live blur + the card's own blurred cover (colourful)
/// + light tint + hairline edge, all clipped to the card shape.
struct FrostedArtworkCardBackground: View {
    var artworkURL: String?
    var tint: Color
    var radius: CGFloat = M3Shape.extraLargeIncreased

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(M3Frost.material).saturation(M3Frost.saturation)
            if let artworkURL {
                BlurredArtwork(url: artworkURL, radius: M3Frost.artworkBlurRadius)
                    .opacity(M3Frost.artworkOpacity)
            }
            tint.opacity(M3Frost.tintOpacity(.card))
            // Keeps white text legible on very bright covers.
            LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.18)], startPoint: .top, endPoint: .bottom)
        }
        .clipShape(shape)
        .overlay(shape.stroke(.white.opacity(M3Frost.edgeOpacity), lineWidth: M3Frost.edgeWidth))
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Pre-blurred artwork

/// Background blur of images with a small memory cache.
final class BlurredImageCache: @unchecked Sendable {
    static let shared = BlurredImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private let context = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])

    private init() {
        cache.countLimit = 120
    }

    func cached(_ key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    /// Downsamples to `side` px, blurs with `radius` (in output pixels),
    /// boosts saturation slightly so the tint stays colourful.
    func blurred(_ image: UIImage, key: String, side: CGFloat = 96, radius: Double = 14) async -> UIImage? {
        if let hit = cached(key) { return hit }
        let result: UIImage? = await Task.detached(priority: .utility) { [context] in
            guard let cg = image.cgImage else { return nil }
            let input = CIImage(cgImage: cg)
            let scale = side / max(input.extent.width, input.extent.height)
            let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

            let clamp = small.clampedToExtent()
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = clamp
            blur.radius = Float(radius)
            let color = CIFilter.colorControls()
            color.inputImage = blur.outputImage
            color.saturation = Float(M3Frost.saturation)
            guard let output = color.outputImage?.cropped(to: small.extent),
                  let rendered = context.createCGImage(output, from: small.extent) else { return nil }
            return UIImage(cgImage: rendered)
        }.value
        if let result { cache.setObject(result, forKey: key as NSString) }
        return result
    }
}

/// Soft, blurred version of a cover (by URL or image), scaled to fill.
struct BlurredArtwork: View {
    var url: String?
    var image: UIImage?
    var radius: Double = 14

    @State private var blurred: UIImage?

    var body: some View {
        // Takes exactly the proposed size: the filled image is an overlay
        // of a size-neutral Color.clear and is clipped to it. (A ZStack would
        // adopt the overflowing scaledToFill size — backgrounds then spilled
        // over neighbouring cards and clipShape lost the rounded corners.)
        Color.clear
            .overlay {
                if let blurred {
                    Image(uiImage: blurred)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .animation(M3Motion.quickFade, value: blurred != nil)
            .task(id: cacheKey) { await load() }
    }

    private var cacheKey: String {
        if let image { return "img-\(ObjectIdentifier(image).hashValue)-\(radius)" }
        return "url-\(url ?? "")-\(radius)"
    }

    private func load() async {
        if let hit = BlurredImageCache.shared.cached(cacheKey) {
            blurred = hit
            return
        }
        var source = image
        if source == nil, let url, let u = URL(string: url) {
            source = ArtworkLoader.cachedImage(for: u)
            if source == nil { source = try? await ArtworkLoader.image(for: u) }
        }
        guard let source else { return }
        blurred = await BlurredImageCache.shared.blurred(source, key: cacheKey, radius: radius)
    }
}

// MARK: - Frosted top chrome

private struct FrostedTopChrome<Header: View>: ViewModifier {
    @Environment(\.m3) private var m3
    @ViewBuilder var header: () -> Header

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                header()
                    .background {
                        // Content scrolls underneath and shows through blurred.
                        FrostedSurface(tint: m3.surface, role: .chrome)
                            .ignoresSafeArea(edges: .top)
                    }
            }
    }
}

extension View {
    /// Pins `header` at the top with a frosted background; the scrollable
    /// content runs underneath it.
    func frostedTopChrome<Header: View>(@ViewBuilder _ header: @escaping () -> Header) -> some View {
        modifier(FrostedTopChrome(header: header))
    }
}

// MARK: - Frosted bar for detail pages

private struct FrostedDetailBar: ViewModifier {
    @Environment(\.m3) private var m3
    let title: String
    /// 0 = hidden (over the hero), 1 = fully visible.
    let progress: CGFloat

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            Text(title)
                .font(.m3(.titleMedium, weight: .medium))
                .foregroundStyle(m3.onSurface)
                .lineLimit(1)
                .padding(.horizontal, 64)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background {
                    FrostedSurface(tint: m3.surface, role: .chrome)
                        .ignoresSafeArea(edges: .top)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(m3.outlineVariant.opacity(0.5)).frame(height: 0.5)
                }
                .opacity(Double(progress))
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Frosted title bar that fades in once the detail hero scrolled away.
    func frostedDetailBar(title: String, progress: CGFloat) -> some View {
        modifier(FrostedDetailBar(title: title, progress: min(max(progress, 0), 1)))
    }
}
