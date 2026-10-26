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

// MARK: - Live frosted surface

struct FrostedSurface<S: Shape>: View {
    var shape: S
    /// Tint laid over the blur (surface colour or artwork colour).
    var tint: Color
    var tintOpacity: Double = 0.55
    /// Thicker material = stronger blur of what's behind.
    var material: Material = .thinMaterial

    var body: some View {
        ZStack {
            shape.fill(material)
            shape.fill(tint.opacity(tintOpacity))
        }
        .environment(\.colorScheme, .dark)
        .compositingGroup()
    }
}

extension FrostedSurface where S == Rectangle {
    init(tint: Color, tintOpacity: Double = 0.55, material: Material = .thinMaterial) {
        self.init(shape: Rectangle(), tint: tint, tintOpacity: tintOpacity, material: material)
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
            color.saturation = 1.25
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
        ZStack {
            if let blurred {
                Image(uiImage: blurred)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
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
