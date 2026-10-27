//
//  Frosted.swift
//  Resona
//
//  Flat, matte frosted-glass surfaces (Android-17 style blur) — explicitly
//  NOT Liquid Glass: no refraction, no specular highlights, no glassEffect.
//
//  Two tools:
//  • ResonaGlassBackground — the single live-blur surface (system material,
//    matte because the app opts out of Liquid Glass) with the cover tint on
//    top, used by every blurred element in the app.
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

/// The ONE set of glass values used everywhere (mini player, navigation
/// bar, sheets, menus, dialogs, cards): same blur strength, same cover
/// tint, same saturation, same edge.
enum ResonaGlass {
    /// System blur (rendered matte because the app opts out of Liquid Glass).
    static let material: Material = .thinMaterial
    /// Share of the cover colour (CoverPalette.main) in the tint.
    static let coverMix = 0.6
    /// Tint over the blur — content behind stays visible but calm.
    static let tintOpacity = 0.42
    /// Saturation boost of what shows through.
    static let saturation = 1.4
    /// 1 px light edge.
    static let edgeOpacity = 0.12
    static let edgeWidth: CGFloat = 1
    /// Pre-blurred artwork (Core Image) radius, in 96 px space.
    static let artworkBlurRadius = 12.0
    /// How strongly a card's own blurred cover shows under the glass.
    static let artworkOpacity = 0.8
}

// MARK: - Glass background

/// The app's only blur surface. Tint = surface mixed with the cover colour
/// (CoverPalette.main, same as the player background), so every glass
/// element carries the cover
/// colour and changes with it (animated by ThemeStore).
struct ResonaGlassBackground<S: Shape>: View {
    @Environment(\.m3) private var m3
    @Environment(\.coverPalette) private var palette
    var shape: S
    /// Cards: the item's own cover, pre-blurred, shows under the glass.
    var artworkURL: String?
    var edge = true

    var body: some View {
        // Same cover colour as the player background (CoverPalette.main),
        // so mini player and player read as one colour.
        let tint = m3.surfaceContainer.mix(with: palette.main.color, by: ResonaGlass.coverMix)
        ZStack {
            shape.fill(ResonaGlass.material)
                .saturation(ResonaGlass.saturation)
            if let artworkURL {
                BlurredArtwork(url: artworkURL, radius: ResonaGlass.artworkBlurRadius)
                    .opacity(ResonaGlass.artworkOpacity)
                    .clipShape(shape)
            }
            shape.fill(tint.opacity(ResonaGlass.tintOpacity))
            if artworkURL != nil {
                // Keeps white text legible on very bright covers.
                LinearGradient(colors: [.clear, .black.opacity(0.18)], startPoint: .top, endPoint: .bottom)
                    .clipShape(shape)
            }
            if edge {
                shape.stroke(.white.opacity(ResonaGlass.edgeOpacity), lineWidth: ResonaGlass.edgeWidth)
            }
        }
        .environment(\.colorScheme, .dark)
        .compositingGroup()
    }
}

extension ResonaGlassBackground where S == Rectangle {
    /// Full-bleed glass (sheets, bars) — no edge.
    init() {
        self.init(shape: Rectangle(), edge: false)
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
            color.saturation = Float(ResonaGlass.saturation)
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
                        ResonaGlassBackground()
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
                    ResonaGlassBackground()
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
