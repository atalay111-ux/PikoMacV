import AppKit
import CoreGraphics

/// Tanılama: yalnızca `--debug-hooks` ile kullanılır. Uygulamanın kendi penceresini (gerçek görünümler, gerçek veri)
/// pencere sunucusundan alır, sentetik bir masaüstü arka planı ve gölge ile birleştirir.
/// Ekran Kaydı izni gerekmez: yalnızca uygulamanın kendi penceresi okunur.
@MainActor
enum DebugCapture {
    private typealias WindowListImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    /// `CGWindowListCreateImage` yeni SDK'larda "kullanılamaz" işaretli olduğundan dlsym ile çözülür.
    static func windowImage(_ window: NSWindow) -> CGImage? {
        guard window.windowNumber > 0,
              let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let fn = unsafeBitCast(sym, to: WindowListImage.self)
        // IncludingWindow(8); BoundsIgnoreFraming(1) | BestResolution(8)
        return fn(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue()
    }

    /// Katman tabanlı yedek: pencerenin içerik görünümünü 2x ölçekte çizer.
    static func viewImage(_ view: NSView) -> CGImage? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage
    }

    static func isDark(_ window: NSWindow) -> Bool {
        window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// `content` piksel görüntüsünü (ölçek `scale`) masaüstü benzeri bir arka plan üstüne yerleştirir.
    static func compose(content: CGImage, scale: CGFloat, dark: Bool, cornerRadius: CGFloat, padding: CGFloat = 40) -> Data? {
        let cw = CGFloat(content.width), ch = CGFloat(content.height)
        let pad = padding * scale
        let w = Int(cw + pad * 2), h = Int(ch + pad * 2)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        drawBackdrop(ctx, rect: full, dark: dark, scale: scale)

        let inner = CGRect(x: pad, y: pad, width: cw, height: ch)
        let radius = cornerRadius * scale
        let path = CGPath(roundedRect: inner, cornerWidth: radius, cornerHeight: radius, transform: nil)
        // Gölge: yalnızca pencerenin dışına düşer (yarı saydam içeriğin altı koyulaşmasın).
        ctx.saveGState()
        ctx.addRect(full)
        ctx.addPath(path)
        ctx.clip(using: .evenOdd)
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 28 * scale,
                      color: CGColor(gray: 0, alpha: dark ? 0.55 : 0.28))
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
        // Gerçek pencere içeriği
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        ctx.draw(content, in: inner)
        ctx.restoreGState()
        guard let out = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: out)
        rep.size = NSSize(width: CGFloat(w) / scale, height: CGFloat(h) / scale)
        return rep.representation(using: .png, properties: [:])
    }

    private static func drawBackdrop(_ ctx: CGContext, rect: CGRect, dark: Bool, scale: CGFloat) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors: [CGColor] = dark
            ? [CGColor(red: 0.10, green: 0.12, blue: 0.20, alpha: 1), CGColor(red: 0.22, green: 0.14, blue: 0.28, alpha: 1)]
            : [CGColor(red: 0.78, green: 0.86, blue: 0.97, alpha: 1), CGColor(red: 0.95, green: 0.84, blue: 0.93, alpha: 1)]
        let g = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: [0, 1])!
        ctx.saveGState()
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.height), end: CGPoint(x: rect.width, y: 0), options: [])
        // Yumuşak renk lekeleri
        let blobs: [(CGFloat, CGFloat, CGFloat, CGColor)] = dark
            ? [(0.2, 0.75, 0.55, CGColor(red: 0.30, green: 0.40, blue: 0.80, alpha: 0.35)),
               (0.85, 0.25, 0.60, CGColor(red: 0.70, green: 0.30, blue: 0.60, alpha: 0.30))]
            : [(0.2, 0.75, 0.55, CGColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 0.55)),
               (0.85, 0.25, 0.60, CGColor(red: 1.0, green: 0.70, blue: 0.80, alpha: 0.50))]
        for (fx, fy, fr, c) in blobs {
            let center = CGPoint(x: rect.width * fx, y: rect.height * fy)
            let r = max(rect.width, rect.height) * fr
            let rg = CGGradient(colorsSpace: cs, colors: [c, c.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(rg, startCenter: center, startRadius: 0, endCenter: center, endRadius: r, options: [])
        }
        ctx.restoreGState()
    }
}
