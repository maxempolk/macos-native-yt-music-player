import AppKit
import CoreImage

/// Extracts a pleasant dominant tint from album artwork for the ambient
/// background. Uses the image's average color, then nudges saturation/brightness
/// so the wash reads nicely in both light and dark mode.
enum ImageColor {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func dominant(from image: NSImage) -> NSColor? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cg = bitmap.cgImage else { return nil }

        let ci = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ci,
            kCIInputExtentKey: CIVector(cgRect: ci.extent),
        ]), let output = filter.outputImage else { return nil }

        var px = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &px, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)

        let avg = NSColor(srgbRed: CGFloat(px[0]) / 255,
                          green: CGFloat(px[1]) / 255,
                          blue: CGFloat(px[2]) / 255,
                          alpha: 1)

        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        avg.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        s = min(1, s * 1.4 + 0.08)          // a bit more vivid than a muddy mean
        b = min(max(b, 0.28), 0.82)         // keep it usable as a background
        return NSColor(hue: h, saturation: s, brightness: b, alpha: 1)
    }
}
