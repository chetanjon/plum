import AppKit
import SwiftUI

/// Pulls a single quiet accent color out of album artwork.
/// Downsample + hue-bucket, not an area average, averaging colorful
/// art yields muddy brown.
enum AccentExtractor {
    /// nil means the artwork is effectively monochrome; callers should
    /// fall back to `Theme.accentFallback`.
    static func accent(from image: NSImage) -> Color? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let side = 24
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)

        struct Bucket {
            var count = 0
            var hue = 0.0
            var saturation = 0.0
            var brightness = 0.0
        }
        var buckets = [Bucket](repeating: Bucket(), count: 12)
        let total = side * side

        for i in 0..<total {
            guard pixels[i * 4 + 3] > 0 else { continue }
            let r = Double(pixels[i * 4]) / 255
            let g = Double(pixels[i * 4 + 1]) / 255
            let b = Double(pixels[i * 4 + 2]) / 255
            let (h, s, v) = hsb(r: r, g: g, b: b)
            // Ignore near-black borders and washed-out pixels; the
            // saturation floor already excludes white text and gray fills.
            guard v >= 0.15, s >= 0.2 else { continue }
            let index = min(11, Int(h * 12))
            buckets[index].count += 1
            buckets[index].hue += h
            buckets[index].saturation += s
            buckets[index].brightness += v
        }

        guard let best = buckets.max(by: { $0.count < $1.count }),
              best.count >= total / 20
        else { return nil }

        let count = Double(best.count)
        // Clamp so even neon plumrs come out restrained and readable.
        return Color(
            hue: best.hue / count,
            saturation: min(best.saturation / count, 0.5),
            brightness: min(max(best.brightness / count, 0.65), 0.82)
        )
    }

    private static func hsb(r: Double, g: Double, b: Double) -> (Double, Double, Double) {
        let maxC = max(r, g, b)
        let delta = maxC - min(r, g, b)
        guard delta > 0 else { return (0, 0, maxC) }
        var hue: Double
        switch maxC {
        case r: hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) / 6
        case g: hue = (((b - r) / delta) + 2) / 6
        default: hue = (((r - g) / delta) + 4) / 6
        }
        if hue < 0 { hue += 1 }
        return (hue, delta / maxC, maxC)
    }
}
