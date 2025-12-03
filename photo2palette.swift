#!/usr/bin/env swift
//
//  photo2palette.swift
//  Created by Michael Stebel on 8/8/25.
//  Updated on 12/3/25.
//
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - CLI Config
struct Config {
    var imagePath: String = ""
    var name: String = "Imported Palette"
    var steps: Int = 512
    var vertical: Bool = false        // sample a column instead of a row
    var format: String = "swift"      // "swift" or "json"

    // Optional adjustments (OFF by default for fidelity)
    var satBoost: Double = 1.0
    var gamma: Double = 1.0
    var stretch: Bool = false
}

// MARK: - CLI Parsing
func parseArgs() -> Config {
    var cfg = Config()
    var it = CommandLine.arguments.dropFirst().makeIterator()

    func next() -> String? { it.next() }

    while let arg = next() {
        switch arg {
        case "-i", "--image":
            if let v = next() { cfg.imagePath = v }

        case "-n", "--name":
            if let v = next() { cfg.name = v }

        case "-s", "--steps":
            if let v = next(), let val = Int(v), val > 1 {
                cfg.steps = val
            }

        case "-v", "--vertical":
            cfg.vertical = true

        case "-f", "--format":
            if let v = next() { cfg.format = v }

        case "--sat":
            if let v = next(), let d = Double(v) { cfg.satBoost = d }

        case "--gamma":
            if let v = next(), let d = Double(v) { cfg.gamma = d }

        case "--stretch":
            cfg.stretch = true

        case "-h", "--help":
            printUsageAndExit()

        default:
            // First non-flag: treat as image path
            if cfg.imagePath.isEmpty {
                cfg.imagePath = arg
            } else {
                fputs("⚠️  Unknown argument: \(arg)\n", stderr)
            }
        }
    }

    if cfg.imagePath.isEmpty {
        printUsageAndExit()
    }
    return cfg
}

func printUsageAndExit() -> Never {
    let exe = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "photo2palette"
    print("""
    \(exe) – Sample an image into a Mandelbrot Metal palette

    Usage:
      \(exe) -i /path/to/image.png [options]

    Required:
      -i, --image <path>       Input image path

    Optional:
      -n, --name <name>        Palette name (default: "Imported Palette")
      -s, --steps <N>          Number of stops (default: 512)
      -v, --vertical           Sample a vertical column instead of a horizontal row
      -f, --format <swift|json>
                               Output format:
                                 swift – PaletteOption.registerCustom(...) code
                                 json  – Mandelbrot Metal palette JSON file

    Adjustments (applied after sampling, OFF by default):
      --sat <factor>           Saturation multiplier (e.g., 1.2 = 20% boost, default 1.0)
      --gamma <value>          Gamma correction (e.g., 0.8 for brighter midtones, default 1.0)
      --stretch                Stretch luminance to full 0–1 range

    Examples:
      \(exe) -i strip.png -n "From Photo" > FromPhoto.swift
      \(exe) -i strip.png -n "From Photo" -f json > FromPhoto.palette.json

    """)
    exit(1)
}

// MARK: - Image Loading

func loadCGImage(_ path: String) -> CGImage? {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, [
        kCGImageSourceShouldCache: false as CFBoolean
    ] as CFDictionary)
}

/// Convert arbitrary image to a straight 8-bit RGBA buffer in sRGB.
func makeSRGBA8Image(from cg: CGImage, width: Int, height: Int) -> (CGImage, Data)? {
    let w = width
    let h = height
    guard w > 0, h > 0 else { return nil }

    let bitsPerComponent = 8
    let bytesPerPixel = 4
    let bpr = w * bytesPerPixel
    var backing = Data(count: h * bpr)

    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let bitmapInfo = CGBitmapInfo(
        rawValue:
            CGImageAlphaInfo.premultipliedLast.rawValue |
            CGBitmapInfo.byteOrder32Big.rawValue
    )

    var outImage: CGImage?

    backing.withUnsafeMutableBytes { ptr in
        guard let addr = ptr.baseAddress else { return }
        let ctx = CGContext(
            data: addr,
            width: w,
            height: h,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bpr,
            space: cs,
            bitmapInfo: bitmapInfo.rawValue
        )
        guard let ctx = ctx else { return }

        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        outImage = ctx.makeImage()
    }

    guard let cgOut = outImage else { return nil }
    return (cgOut, backing)
}

// MARK: - Color helpers
struct RGB { var r: Double; var g: Double; var b: Double }

/// Convert a hex string like "#RRGGBB" or "RRGGBB" into normalized RGB (0–1).
func hexToRGB(_ hex: String) -> RGB? {
    var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if hexString.hasPrefix("#") {
        hexString.removeFirst()
    }
    guard hexString.count == 6 else { return nil }

    var value: UInt64 = 0
    guard Scanner(string: hexString).scanHexInt64(&value) else {
        return nil
    }

    let r = Double((value >> 16) & 0xFF) / 255.0
    let g = Double((value >> 8) & 0xFF) / 255.0
    let b = Double(value & 0xFF) / 255.0
    return RGB(r: r, g: g, b: b)
}

@inline(__always) func clamp(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(max(x, a), b) }

func rgbToHsl(_ c: RGB) -> (h: Double, s: Double, l: Double) {
    let r=c.r, g=c.g, b=c.b
    let maxv = max(r, max(g, b)), minv = min(r, min(g, b))
    let l = (maxv + minv) / 2
    var h = 0.0, s = 0.0
    if maxv != minv {
        let d = maxv - minv
        s = l > 0.5 ? d / (2.0 - maxv - minv) : d / (maxv + minv)
        if maxv == r {
            h = (g - b) / d + (g < b ? 6 : 0)
        } else if maxv == g {
            h = (b - r) / d + 2
        } else {
            h = (r - g) / d + 4
        }
        h /= 6
    }
    return (h,s,l)
}

func hslToRgb(h: Double, s: Double, l: Double) -> RGB {
    if s == 0 {
        return RGB(r: l, g: l, b: l)
    }
    func hueToRGB(_ p: Double, _ q: Double, _ t: Double) -> Double {
        var t = t
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1/6 { return p + (q - p) * 6 * t }
        if t < 1/2 { return q }
        if t < 2/3 { return p + (q - p) * (2/3 - t) * 6 }
        return p
    }
    let q = l < 0.5 ? l * (1 + s) : l + s - l*s
    let p = 2*l - q
    let r = hueToRGB(p, q, h + 1/3)
    let g = hueToRGB(p, q, h)
    let b = hueToRGB(p, q, h - 1/3)
    return RGB(r:r, g:g, b:b)
}

func applySatGammaStretch(_ rgb: RGB, sat: Double, gamma: Double, stretch: Bool) -> RGB {
    var c = rgb

    // 1) Convert to HSL and apply saturation multiplier.
    if sat != 1.0 {
        let hsl = rgbToHsl(c)
        let newS = clamp(hsl.s * sat, 0, 1)
        c = hslToRgb(h: hsl.h, s: newS, l: hsl.l)
    }

    // 2) Apply gamma to each channel in linear fashion.
    if gamma != 1.0 {
        c.r = pow(clamp(c.r), 1.0/gamma)
        c.g = pow(clamp(c.g), 1.0/gamma)
        c.b = pow(clamp(c.b), 1.0/gamma)
    }

    // 3) Stretch luminance to 0–1 if requested.
    if stretch {
        let lumMin = min(c.r, min(c.g, c.b))
        let lumMax = max(c.r, max(c.g, c.b))
        let range = lumMax - lumMin
        if range > 1e-6 {
            c.r = clamp((c.r - lumMin) / range)
            c.g = clamp((c.g - lumMin) / range)
            c.b = clamp((c.b - lumMin) / range)
        }
    }
    return c
}

func hex(_ c: RGB) -> String {
    let r = UInt8(clamp(c.r) * 255.0 + 0.5)
    let g = UInt8(clamp(c.g) * 255.0 + 0.5)
    let b = UInt8(clamp(c.b) * 255.0 + 0.5)
    return String(format: "#%02X%02X%02X", r, g, b)
}

// MARK: - Sampling

func extractStops(from cg: CGImage, cfg: Config) -> [(Double, String)]? {
    let targetW = cfg.vertical ? max(1, Int(round(Double(cg.width)  * Double(cfg.steps) / Double(max(cg.height,1))))) : cfg.steps
    let targetH = cfg.vertical ? cfg.steps : max(1, Int(round(Double(cg.height) * Double(cfg.steps) / Double(max(cg.width,1)))))

    guard let (_, rgbaData) = makeSRGBA8Image(from: cg, width: targetW, height: targetH) else { return nil }
    let bytes = [UInt8](rgbaData) // RGBA

    let bpr = targetW * 4
    var out: [(Double, String)] = []
    out.reserveCapacity(cfg.steps)

    if cfg.vertical {
        let x = max(0, min(targetW-1, targetW/2))
        for i in 0..<cfg.steps {
            let y = Int(round(Double(i) / Double(cfg.steps-1) * Double(max(targetH-1,0))))
            let p = y * bpr + x * 4
            let rgb = RGB(r: Double(bytes[p+0])/255.0, g: Double(bytes[p+1])/255.0, b: Double(bytes[p+2])/255.0)
            let adj = applySatGammaStretch(rgb, sat: cfg.satBoost, gamma: cfg.gamma, stretch: cfg.stretch)
            let t = Double(i) / Double(cfg.steps-1)
            out.append((t, hex(adj)))
        }
    } else {
        let y = max(0, min(targetH-1, targetH/2))
        for i in 0..<cfg.steps {
            let x = Int(round(Double(i) / Double(cfg.steps-1) * Double(max(targetW-1,0))))
            let p = y * bpr + x * 4
            let rgb = RGB(r: Double(bytes[p+0])/255.0, g: Double(bytes[p+1])/255.0, b: Double(bytes[p+2])/255.0)
            let adj = applySatGammaStretch(rgb, sat: cfg.satBoost, gamma: cfg.gamma, stretch: cfg.stretch)
            let t = Double(i) / Double(cfg.steps-1)
            out.append((t, hex(adj)))
        }
    }
    return out
}

// MARK: - Output
func printSwift(name: String, stops: [(Double, String)]) {
    print("""
    // Paste into PaletteOption.swift (inside init or registration area)
    self.registerCustom(
        name: "\(name)",
        stops: [
    """)
    for (i, s) in stops.enumerated() {
        let t = s.0
        let hex = s.1
        let comma = (i == stops.count - 1) ? "" : ","
        print("            (\(String(format: "%.15f", t)), \"\(hex)\")\(comma)")
    }
    print("""
        ]
    )
    """)
}

func printJSON(name: String, stops: [(Double, String)]) {
    // Emit Mandelbrot Metal-compatible palette JSON:
    // {
    //   "colorSpace": "display-p3",
    //   "name": "<name>",
    //   "schemaVersion": 1,
    //   "stops": [
    //     { "r": <Double>, "g": <Double>, "b": <Double>, "t": <Double> },
    //     ...
    //   ]
    // }
    let convertedStops: [[String: Any]] = stops.compactMap { (t, hex) in
        guard let rgb = hexToRGB(hex) else { return nil }
        return [
            "r": rgb.r,
            "g": rgb.g,
            "b": rgb.b,
            "t": t
        ]
    }

    let dict: [String: Any] = [
        "colorSpace": "display-p3",
        "name": name,
        "schemaVersion": 1,
        "stops": convertedStops
    ]

    let data = try! JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
    print(String(data: data, encoding: .utf8)!)
}

// MARK: - Main
let cfg = parseArgs()
guard let cg = loadCGImage(cfg.imagePath) else {
    fputs("❌ Could not load image at \(cfg.imagePath)\n", stderr)
    exit(2)
}
guard let stops = extractStops(from: cg, cfg: cfg) else {
    fputs("❌ Failed to sample\n", stderr)
    exit(2)
}
switch cfg.format.lowercased() {
case "json":  printJSON(name: cfg.name, stops: stops)
default:      printSwift(name: cfg.name, stops: stops)
}
