#!/usr/bin/env swift
//
//  photo2palette.swift
//  Mandelbrot Metal 3.0 palette utility
//
//  Created by Michael Stebel on 8/8/25.
//  Updated for Mandelbrot Metal 3.0 on 8/29/26.
//

import Foundation
import CoreGraphics
import ImageIO

private let toolVersion = "3.0.0"
private let paletteSchemaVersion = 1

private enum OutputFormat: String {
    case json
    case swift
}

private enum SamplingAxis: String {
    case auto
    case horizontal
    case vertical
}

private enum PaletteColorSpace: String {
    case sRGB = "srgb"
    case displayP3 = "display-p3"

    var cg: CGColorSpace {
        switch self {
        case .sRGB:
            return CGColorSpace(name: CGColorSpace.sRGB)!
        case .displayP3:
            return CGColorSpace(name: CGColorSpace.displayP3)!
        }
    }
}

private struct Config {
    var imagePath = ""
    var name = "Imported Palette"
    var steps = 1024
    var anchors = 64
    var exact = false
    var axis: SamplingAxis = .auto
    var format: OutputFormat = .json
    var colorSpace: PaletteColorSpace = .displayP3
    var saturation = 1.12
    var gamma = 0.95
    var stretch = true
    var stretchFactor = 1.2
    var outputPath: String?
}

private struct RGB {
    var r: Double
    var g: Double
    var b: Double
}

private struct PaletteStop {
    var t: Double
    var color: RGB
}

private struct JSONPaletteStop: Codable {
    let b: Double
    let g: Double
    let r: Double
    let t: Double
}

private struct JSONPalette: Codable {
    let colorSpace: String
    let name: String
    let schemaVersion: Int
    let stops: [JSONPaletteStop]
    let type: String
}

private enum CLIError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text): return text
        }
    }
}

@inline(__always)
private func clamp(_ value: Double, _ lower: Double = 0, _ upper: Double = 1) -> Double {
    min(max(value, lower), upper)
}

private func usage(tool: String) -> String {
    """
    photo2palette \(toolVersion) — Create Mandelbrot Metal 3.0 palettes from images

    Usage:
      \(tool) --image <path> [options]

    Required:
      -i, --image <path>          Source image (PNG, JPEG, HEIC, and other ImageIO formats)

    Palette:
      -n, --name <name>           Palette name (default: "Imported Palette")
      -s, --steps <2...16384>     Source sampling resolution (default: 1024)
          --anchors <2...16384>   Compact output stop count (default: 64)
          --exact                 Keep every sampled stop instead of compact anchors
          --compact               Emit compact anchors (default)
          --axis <mode>           auto, horizontal, or vertical (default: auto)
      -v, --vertical              Alias for --axis vertical
          --horizontal            Alias for --axis horizontal

    Color:
          --color-space <space>   display-p3 or srgb (default: display-p3)
          --sat <0.5...2.0>       Saturation multiplier (default: 1.12)
          --gamma <0.60...1.40>   Gamma correction (default: 0.95)
          --stretch               Enable v3 contrast stretch (default)
          --no-stretch            Disable contrast stretch
          --stretch-factor <n>    Advanced contrast factor (default: 1.2)

    Output:
      -f, --format <json|swift>   Importable JSON (default) or developer Swift
      -o, --output <path>         Write atomically to a file instead of stdout

    General:
      -h, --help                  Show this help
          --version               Show CLI and palette schema versions

    Examples:
      \(tool) -i sunset.jpg -n "Sunset" -o Sunset.mandelpalette.json
      \(tool) -i aurora.heic -n "Aurora Exact" --exact --color-space display-p3 \
        -o Aurora-Exact.mandelpalette.json
      \(tool) -i strip.png --axis horizontal --color-space srgb --format swift

    JSON remains palette schema v\(paletteSchemaVersion), compatible with Mandelbrot Metal 2.x and 3.x.
    """
}

private func parseDouble(_ raw: String, option: String) throws -> Double {
    guard let value = Double(raw), value.isFinite else {
        throw CLIError.message("\(option) requires a finite number; received '\(raw)'.")
    }
    return value
}

private func parseInteger(_ raw: String, option: String) throws -> Int {
    guard let value = Int(raw) else {
        throw CLIError.message("\(option) requires an integer; received '\(raw)'.")
    }
    return value
}

private func parseArguments() throws -> Config {
    let arguments = CommandLine.arguments
    let tool = (arguments.first as NSString?)?.lastPathComponent ?? "photo2palette"

    if arguments.dropFirst().contains("--version") {
        print("photo2palette \(toolVersion) (Mandelbrot Metal palette schema \(paletteSchemaVersion))")
        exit(0)
    }
    if arguments.dropFirst().contains("-h") || arguments.dropFirst().contains("--help") {
        print(usage(tool: tool))
        exit(0)
    }

    var config = Config()
    var index = 1

    func requiredValue(for option: String) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count, !arguments[valueIndex].hasPrefix("-") else {
            throw CLIError.message("Missing value for \(option).")
        }
        index = valueIndex
        return arguments[valueIndex]
    }

    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "-i", "--image":
            config.imagePath = try requiredValue(for: argument)
        case "-n", "--name":
            config.name = try requiredValue(for: argument)
        case "-s", "--steps":
            config.steps = try parseInteger(try requiredValue(for: argument), option: argument)
        case "--anchors":
            config.anchors = try parseInteger(try requiredValue(for: argument), option: argument)
        case "--exact":
            config.exact = true
        case "--compact":
            config.exact = false
        case "--axis":
            let raw = try requiredValue(for: argument).lowercased()
            guard let axis = SamplingAxis(rawValue: raw) else {
                throw CLIError.message("Unsupported axis '\(raw)'; use auto, horizontal, or vertical.")
            }
            config.axis = axis
        case "-v", "--vertical":
            config.axis = .vertical
        case "--horizontal":
            config.axis = .horizontal
        case "-f", "--format":
            let raw = try requiredValue(for: argument).lowercased()
            guard let format = OutputFormat(rawValue: raw) else {
                throw CLIError.message("Unsupported format '\(raw)'; use json or swift.")
            }
            config.format = format
        case "--color-space":
            let raw = try requiredValue(for: argument).lowercased()
            guard let colorSpace = PaletteColorSpace(rawValue: raw) else {
                throw CLIError.message("Unsupported color space '\(raw)'; use display-p3 or srgb.")
            }
            config.colorSpace = colorSpace
        case "--sat":
            config.saturation = try parseDouble(try requiredValue(for: argument), option: argument)
        case "--gamma":
            config.gamma = try parseDouble(try requiredValue(for: argument), option: argument)
        case "--stretch":
            config.stretch = true
            if index + 1 < arguments.count,
               !arguments[index + 1].hasPrefix("-"),
               let legacyFactor = Double(arguments[index + 1]) {
                index += 1
                config.stretchFactor = legacyFactor
                fputs("Warning: '--stretch <number>' is deprecated; use '--stretch-factor <number>'.\n", stderr)
            }
        case "--no-stretch":
            config.stretch = false
        case "--stretch-factor":
            config.stretchFactor = try parseDouble(try requiredValue(for: argument), option: argument)
            config.stretch = true
        case "-o", "--output":
            config.outputPath = try requiredValue(for: argument)
        default:
            throw CLIError.message("Unknown argument '\(argument)'.")
        }
        index += 1
    }

    guard !config.imagePath.isEmpty else {
        throw CLIError.message("Missing required --image <path>.")
    }
    guard !config.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw CLIError.message("Palette name must not be empty.")
    }
    guard (2...16_384).contains(config.steps) else {
        throw CLIError.message("--steps must be between 2 and 16384.")
    }
    guard (2...16_384).contains(config.anchors) else {
        throw CLIError.message("--anchors must be between 2 and 16384.")
    }
    guard (0.5...2.0).contains(config.saturation) else {
        throw CLIError.message("--sat must be between 0.5 and 2.0 to match Mandelbrot Metal 3.0.")
    }
    guard (0.60...1.40).contains(config.gamma) else {
        throw CLIError.message("--gamma must be between 0.60 and 1.40 to match Mandelbrot Metal 3.0.")
    }
    guard config.stretchFactor.isFinite, (0.1...4.0).contains(config.stretchFactor) else {
        throw CLIError.message("--stretch-factor must be between 0.1 and 4.0.")
    }
    return config
}

private func loadImage(at path: String) throws -> CGImage {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw CLIError.message("Could not load an image from '\(path)'.")
    }
    guard image.width > 0, image.height > 0 else {
        throw CLIError.message("The source image has invalid dimensions.")
    }
    return image
}

private func applyAdjustments(
    _ input: RGB,
    saturation saturationMultiplier: Double,
    gamma: Double,
    stretch: Bool,
    stretchFactor: Double
) -> RGB {
    let r = clamp(input.r)
    let g = clamp(input.g)
    let b = clamp(input.b)
    let maximum = max(r, max(g, b))
    let minimum = min(r, min(g, b))
    let delta = maximum - minimum

    var hue = 0.0
    var saturation = maximum == 0 ? 0 : delta / maximum
    var value = pow(maximum, gamma)

    if delta > 0 {
        if maximum == r {
            hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == g {
            hue = 60 * (((b - r) / delta) + 2)
        } else {
            hue = 60 * (((r - g) / delta) + 4)
        }
    }

    saturation = clamp(saturation * saturationMultiplier)
    if stretch {
        value = clamp(0.5 + (value - 0.5) * stretchFactor)
    }

    let chroma = value * saturation
    let huePrime = hue / 60
    let x = chroma * (1 - abs(huePrime.truncatingRemainder(dividingBy: 2) - 1))
    let match = value - chroma

    let adjusted: RGB
    switch huePrime {
    case ..<0: adjusted = RGB(r: 0, g: 0, b: 0)
    case ..<1: adjusted = RGB(r: chroma, g: x, b: 0)
    case ..<2: adjusted = RGB(r: x, g: chroma, b: 0)
    case ..<3: adjusted = RGB(r: 0, g: chroma, b: x)
    case ..<4: adjusted = RGB(r: 0, g: x, b: chroma)
    case ..<5: adjusted = RGB(r: x, g: 0, b: chroma)
    case ...6: adjusted = RGB(r: chroma, g: 0, b: x)
    default: adjusted = RGB(r: 0, g: 0, b: 0)
    }

    return RGB(
        r: clamp(adjusted.r + match),
        g: clamp(adjusted.g + match),
        b: clamp(adjusted.b + match)
    )
}

private func rgba8(
    from source: CGImage,
    width: Int,
    height: Int,
    colorSpace: CGColorSpace
) throws -> Data {
    let targetWidth = max(1, width)
    let targetHeight = max(1, height)
    let bitmapInfo = CGBitmapInfo(rawValue:
        CGImageAlphaInfo.premultipliedLast.rawValue |
        CGBitmapInfo.byteOrder32Big.rawValue
    )
    var pixels = Data(count: targetWidth * targetHeight * 4)
    var drewImage = false

    pixels.withUnsafeMutableBytes { buffer in
        guard let base = buffer.baseAddress,
              let context = CGContext(
                data: base,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: targetWidth * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
              ) else { return }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        drewImage = true
    }

    guard drewImage else {
        throw CLIError.message("Could not create the color-managed sampling bitmap.")
    }
    return pixels
}

private func sample(_ image: CGImage, config: Config) throws -> [PaletteStop] {
    let vertical: Bool
    switch config.axis {
    case .auto: vertical = image.height > image.width
    case .horizontal: vertical = false
    case .vertical: vertical = true
    }

    let targetWidth = vertical
        ? max(1, Int(round(Double(image.width) * Double(config.steps) / Double(max(image.height, 1)))))
        : config.steps
    let targetHeight = vertical
        ? config.steps
        : max(1, Int(round(Double(image.height) * Double(config.steps) / Double(max(image.width, 1)))))
    let rgba = try rgba8(
        from: image,
        width: targetWidth,
        height: targetHeight,
        colorSpace: config.colorSpace.cg
    )
    let bytes = [UInt8](rgba)
    let bytesPerRow = targetWidth * 4
    var stops: [PaletteStop] = []
    stops.reserveCapacity(config.steps)

    for index in 0..<config.steps {
        let t = Double(index) / Double(config.steps - 1)
        let x: Int
        let y: Int
        if vertical {
            x = max(0, min(targetWidth - 1, targetWidth / 2))
            y = Int(round(t * Double(max(targetHeight - 1, 0))))
        } else {
            x = Int(round(t * Double(max(targetWidth - 1, 0))))
            y = max(0, min(targetHeight - 1, targetHeight / 2))
        }
        let pixel = y * bytesPerRow + x * 4
        let input = RGB(
            r: Double(bytes[pixel]) / 255,
            g: Double(bytes[pixel + 1]) / 255,
            b: Double(bytes[pixel + 2]) / 255
        )
        stops.append(PaletteStop(
            t: t,
            color: applyAdjustments(
                input,
                saturation: config.saturation,
                gamma: config.gamma,
                stretch: config.stretch,
                stretchFactor: config.stretchFactor
            )
        ))
    }
    return stops
}

private func compact(_ stops: [PaletteStop], anchors: Int) -> [PaletteStop] {
    guard anchors > 1, stops.count > anchors else { return stops }
    return (0..<anchors).map { index in
        let t = Double(index) / Double(anchors - 1)
        let sourceIndex = min(stops.count - 1, Int(round(t * Double(stops.count - 1))))
        return PaletteStop(t: t, color: stops[sourceIndex].color)
    }
}

private func jsonOutput(config: Config, stops: [PaletteStop]) throws -> String {
    let palette = JSONPalette(
        colorSpace: config.colorSpace.rawValue,
        name: config.name,
        schemaVersion: paletteSchemaVersion,
        stops: stops.map {
            JSONPaletteStop(b: $0.color.b, g: $0.color.g, r: $0.color.r, t: $0.t)
        },
        type: "palette"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(palette)
    guard let text = String(data: data, encoding: .utf8) else {
        throw CLIError.message("Could not encode the palette as UTF-8 JSON.")
    }
    return text
}

private func swiftStringLiteral(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
}

private func swiftOutput(config: Config, stops: [PaletteStop]) -> String {
    let colorConstructor: (RGB) -> String = { color in
        switch config.colorSpace {
        case .sRGB:
            return String(
                format: "UIColor(red: %.9f, green: %.9f, blue: %.9f, alpha: 1)",
                locale: Locale(identifier: "en_US_POSIX"),
                color.r, color.g, color.b
            )
        case .displayP3:
            return String(
                format: "UIColor(displayP3Red: %.9f, green: %.9f, blue: %.9f, alpha: 1)",
                locale: Locale(identifier: "en_US_POSIX"),
                color.r, color.g, color.b
            )
        }
    }
    let rows = stops.enumerated().map { index, stop in
        let comma = index == stops.count - 1 ? "" : ","
        return String(
            format: "        (%.9f, %@)%@",
            locale: Locale(identifier: "en_US_POSIX"),
            stop.t,
            colorConstructor(stop.color),
            comma
        )
    }.joined(separator: "\n")
    return """
    // Generated by photo2palette \(toolVersion); source color space: \(config.colorSpace.rawValue)
    PaletteCatalog.shared.registerCustom(
        name: "\(swiftStringLiteral(config.name))",
        stops: [
    \(rows)
        ]
    )
    """
}

private func emit(_ text: String, to outputPath: String?) throws {
    guard let outputPath else {
        print(text)
        return
    }
    let url = URL(fileURLWithPath: outputPath)
    guard let data = (text + "\n").data(using: .utf8) else {
        throw CLIError.message("Could not encode output as UTF-8.")
    }
    do {
        try data.write(to: url, options: .atomic)
        fputs("Wrote \(url.path)\n", stderr)
    } catch {
        throw CLIError.message("Could not write '\(outputPath)': \(error.localizedDescription)")
    }
}

do {
    let config = try parseArguments()
    let image = try loadImage(at: config.imagePath)
    let exactStops = try sample(image, config: config)
    let outputStops = config.exact ? exactStops : compact(exactStops, anchors: config.anchors)
    let output: String
    switch config.format {
    case .json: output = try jsonOutput(config: config, stops: outputStops)
    case .swift: output = swiftOutput(config: config, stops: outputStops)
    }
    try emit(output, to: config.outputPath)
} catch {
    let tool = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "photo2palette"
    fputs("Error: \(error)\n\n\(usage(tool: tool))\n", stderr)
    exit(1)
}
