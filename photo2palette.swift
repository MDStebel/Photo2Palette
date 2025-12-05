#!/usr/bin/env swift
//
//  photo2palette.swift
//  Created by Michael Stebel on 8/8/25.
//  Updated on 12/5/25.
//
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - CLI Config
struct Config {
    var imagePath: String = ""
    var name: String = "Imported Palette"
    var steps: Int = 512              // default number of steps
    var vertical: Bool = false        // default horizontal sampling
    var format: String = "swift"      // "swift" or "json"
    
    // color adjustments
    var satBoost: Double = 1.0        // saturation multiplier
    var gamma: Double = 1.0           // gamma correction
    var stretch: Double = 1.0         // contrast-ish stretch
}

// MARK: - Small Helpers
func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
    return min(max(x, lo), hi)
}

struct RGB {
    var r: Double
    var g: Double
    var b: Double
}

func applySatGammaStretch(_ rgb: RGB, sat: Double, gamma: Double, stretch: Double) -> RGB {
    // 1) convert to HSV for saturation adjustment (approximate)
    
    let r = clamp(rgb.r, 0, 1)
    let g = clamp(rgb.g, 0, 1)
    let b = clamp(rgb.b, 0, 1)
    
    let mx = max(r, max(g, b))
    let mn = min(r, min(g, b))
    let delta = mx - mn
    
    var h: Double = 0
    var s: Double = (mx == 0) ? 0 : (delta / mx)
    let v: Double = mx
    
    if delta > 0 {
        if mx == r {
            h = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
        } else if mx == g {
            h = 60 * (((b - r) / delta) + 2)
        } else {
            h = 60 * (((r - g) / delta) + 4)
        }
    } else {
        h = 0
    }
    
    // 2) adjust saturation
    s *= sat
    s = clamp(s, 0, 1)
    
    // 3) gamma on value
    var vv = pow(v, gamma)
    
    // 4) "stretch" as a simple contrast around 0.5
    vv = 0.5 + (vv - 0.5) * stretch
    vv = clamp(vv, 0, 1)
    
    // 5) convert HSV back to RGB
    let c = vv * s
    let hh = h / 60.0
    let x = c * (1 - abs((hh.truncatingRemainder(dividingBy: 2)) - 1))
    let m = vv - c
    
    var rr = 0.0, gg = 0.0, bb = 0.0
    if hh < 0 {
        rr = 0; gg = 0; bb = 0
    } else if hh < 1 {
        rr = c; gg = x; bb = 0
    } else if hh < 2 {
        rr = x; gg = c; bb = 0
    } else if hh < 3 {
        rr = 0; gg = c; bb = x
    } else if hh < 4 {
        rr = 0; gg = x; bb = c
    } else if hh < 5 {
        rr = x; gg = 0; bb = c
    } else if hh <= 6 {
        rr = c; gg = 0; bb = x
    } else {
        rr = 0; gg = 0; bb = 0
    }
    
    return RGB(r: clamp(rr + m, 0, 1),
               g: clamp(gg + m, 0, 1),
               b: clamp(bb + m, 0, 1))
}

func hex(_ rgb: RGB) -> String {
    let R = Int(round(clamp(rgb.r, 0, 1)*255))
    let G = Int(round(clamp(rgb.g, 0, 1)*255))
    let B = Int(round(clamp(rgb.b, 0, 1)*255))
    return String(format:"#%02X%02X%02X", R, G, B)
}

func hexToRGB(_ hex: String) -> RGB? {
    // Accept #RRGGBB or RRGGBB
    let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard s.count == 6 else { return nil }
    let scanner = Scanner(string: s)
    var val: UInt64 = 0
    guard scanner.scanHexInt64(&val) else { return nil }
    let r = Double((val >> 16) & 0xFF) / 255.0
    let g = Double((val >> 8) & 0xFF) / 255.0
    let b = Double(val & 0xFF) / 255.0
    return RGB(r: r, g: g, b: b)
}

// MARK: - Argument Parsing
func parseArgs() -> Config {
    var cfg = Config()
    
    func usage() {
        let tool = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "photo2palette.swift"
        fputs("""
        photo2palette — Convert an image into a Mandelbrot Metal-compatible palette
        
        Usage:
          \(tool) --image <path> [options]
        
        Required:
          -i, --image <path>       Source image file (PNG, JPG, etc.)
        
        Optional:
          -n, --name <string>      Palette name (default: "\(cfg.name)")
          -s, --steps <int>        Number of samples/steps (default: \(cfg.steps))
          -v, --vertical           Sample a vertical slice (default: horizontal)
          -f, --format <swift|json>
                                   Output format:
                                     swift  = Swift snippet for PaletteOption.swift (default)
                                     json   = Mandelbrot Metal JSON palette file
        
        Color adjustment options:
          --sat <double>           Saturation multiplier (default: \(cfg.satBoost))
          --gamma <double>         Gamma correction on value (default: \(cfg.gamma))
          --stretch <double>       Contrast stretch around midtone (default: \(cfg.stretch))
        
        General:
          -h, --help               Show this help and exit
        
        Examples:
          # Generate Swift code for a custom palette:
          \(tool) --image "source.png" --name "My Palette"
        
          # Generate JSON palette and redirect to a file:
          \(tool) --image "source.png" --name "My Palette" --format json > MyPalette.json
        
          # Use 768 steps vertically with slight saturation boost:
          \(tool) -i source.png -n "Tall Glow" -s 768 -v --sat 1.2
        
        """, stderr)
    }
    
    if CommandLine.arguments.contains("-h") || CommandLine.arguments.contains("--help") {
        usage()
        exit(0)
    }
    
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
            if let v = next(), let val = Double(v) {
                cfg.satBoost = val
            }
            
        case "--gamma":
            if let v = next(), let val = Double(v) {
                cfg.gamma = val
            }
            
        case "--stretch":
            if let v = next(), let val = Double(v) {
                cfg.stretch = val
            }
            
        default:
            fputs("⚠️  Unknown argument: \(arg)\n", stderr)
        }
    }
    
    if cfg.imagePath.isEmpty {
        fputs("❌  Missing required --image <path>\n\n", stderr)
        usage()
        exit(1)
    }
    
    return cfg
}

// MARK: - Image Loading
func loadCGImage(_ path: String) -> CGImage? {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        fputs("❌ Could not create image source for \(path)\n", stderr)
        return nil
    }
    guard let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        fputs("❌ Could not load CGImage from \(path)\n", stderr)
        return nil
    }
    return img
}

// MARK: - Sampling
func extractStops(from cgImage: CGImage, cfg: Config) -> [(Double, String)]? {
    let width = cgImage.width
    let height = cgImage.height
    
    guard width > 0, height > 0 else {
        fputs("❌ Image has invalid dimensions\n", stderr)
        return nil
    }
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerPixel = 4
    let bitsPerComponent = 8
    let bytesPerRow = bytesPerPixel * width
    
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: bitsPerComponent,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fputs("❌ Could not create CGContext\n", stderr)
        return nil
    }
    
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = ctx.data else {
        fputs("❌ Could not get bitmap data\n", stderr)
        return nil
    }
    
    let ptr = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
    
    var out: [(Double, String)] = []
    out.reserveCapacity(cfg.steps)
    
    let targetW = width
    let targetH = height
    let bpr = bytesPerRow
    
    if cfg.vertical {
        let x = max(0, min(targetW-1, targetW/2))
        for i in 0..<cfg.steps {
            let y = Int(round(Double(i) / Double(cfg.steps-1) * Double(max(targetH-1,0))))
            let p = y * bpr + x * 4
            let rgb = RGB(r: Double(ptr[p+0])/255.0, g: Double(ptr[p+1])/255.0, b: Double(ptr[p+2])/255.0)
            let adj = applySatGammaStretch(rgb, sat: cfg.satBoost, gamma: cfg.gamma, stretch: cfg.stretch)
            let t = Double(i) / Double(cfg.steps-1)
            out.append((t, hex(adj)))
        }
    } else {
        let y = max(0, min(targetH-1, targetH/2))
        for i in 0..<cfg.steps {
            let x = Int(round(Double(i) / Double(cfg.steps-1) * Double(max(targetW-1,0))))
            let p = y * bpr + x * 4
            let rgb = RGB(r: Double(ptr[p+0])/255.0, g: Double(ptr[p+1])/255.0, b: Double(ptr[p+2])/255.0)
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
        let comma = (i == stops.count - 1) ? "" : ","
        print(String(format: "            (%.5f, UIColor(hex: \"%@\"))%@", s.0, s.1, comma))
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
    //   ],
    //   "type": "palette"
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
        "stops": convertedStops,
        "type": "palette"
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
