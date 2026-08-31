# Photo2Palette 3.0

Photo2Palette converts an image into a custom palette compatible with Mandelbrot Metal 3.0. It uses the same sampling resolution, compact-anchor policy, color adjustments, automatic sampling axis, and color-space handling as the in-app Custom Palette Studio.

The default output is importable JSON. Swift output remains available for palette-development work.

> Importing, creating, saving, and refining custom palettes are Mandelbrot Metal Pro features in version 3.0. The CLI runs independently, but importing its output into the app requires Pro access.

## What changed for version 3.0

- JSON is now the default output format.
- The default source resolution is 1,024 samples.
- Compact output uses 64 evenly spaced anchors, matching the app.
- The **--exact** option retains all sampled stops for a non-interpolated LUT.
- The sampling axis defaults to **auto**: portrait images use a vertical center slice and landscape or square images use a horizontal center slice.
- Defaults match the app: saturation 1.12, gamma 0.95, and contrast stretch enabled at 1.2.
- Rasterization is explicitly color managed as Display P3 or sRGB.
- JSON RGB values are no longer quantized through hexadecimal conversion.
- Invalid options now fail with a nonzero exit status instead of silently falling back.
- Output can be written atomically with **--output**.
- Palette JSON remains schema version 1 for compatibility with Mandelbrot Metal 2.x and 3.x.

## Installation

Make the script executable:

~~~bash
chmod +x photo2palette.swift
~~~

Run it in place:

~~~bash
./photo2palette.swift --help
~~~

Optionally install it on your command path:

~~~bash
sudo cp photo2palette.swift /usr/local/bin/photo2palette
~~~

## Usage

~~~text
photo2palette --image <path> [options]

Required:
  -i, --image <path>          Source image

Palette:
  -n, --name <name>           Palette name (default: "Imported Palette")
  -s, --steps <2...16384>     Source sampling resolution (default: 1024)
      --anchors <2...16384>   Compact output stop count (default: 64)
      --exact                 Keep every sampled stop
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
  -f, --format <json|swift>   JSON (default) or developer Swift
  -o, --output <path>         Write atomically to a file instead of stdout

General:
  -h, --help                  Show help
      --version               Show CLI and palette schema versions
~~~

The old numeric form **--stretch 1.2** is accepted for compatibility but is deprecated. Use **--stretch** for the v3 behavior or **--stretch-factor 1.2** for an explicit factor.

## Examples

Create a normal v3 palette:

~~~bash
photo2palette \
  --image sunset.jpg \
  --name "Sunset" \
  --output Sunset.mandelpalette.json
~~~

Create an exact 1,024-stop Display P3 palette:

~~~bash
photo2palette \
  --image aurora.heic \
  --name "Aurora Exact" \
  --exact \
  --color-space display-p3 \
  --output Aurora-Exact.mandelpalette.json
~~~

Force a horizontal sRGB sample and write JSON to standard output:

~~~bash
photo2palette \
  --image strip.png \
  --axis horizontal \
  --color-space srgb
~~~

Generate developer Swift:

~~~bash
photo2palette \
  --image strip.png \
  --name "Catalog Candidate" \
  --format swift \
  --exact \
  --color-space display-p3
~~~

Swift output uses the Display P3 UIColor initializer for Display P3 and the standard UIColor RGB initializer for sRGB, preserving the declared component space.

## Compact versus exact palettes

The app first creates a high-quality sample at the selected LUT resolution.

- Compact mode, the default, selects 64 evenly spaced anchors from that sample. Mandelbrot Metal interpolates between them.
- Exact mode retains every sampled stop. With the default settings this produces 1,024 stops and the app uses nearest-sample lookup when Exact LUT is enabled.

Compact palettes are smaller and normally produce smooth gradients. Exact palettes preserve discrete or highly structured source gradients.

## Sampling direction

Automatic direction matches the app:

- Portrait image: vertical center column, top to bottom.
- Landscape or square image: horizontal center row, left to right.

Use **--axis horizontal**, **--axis vertical**, **--horizontal**, or **--vertical** to override this.

Crop the source so the center row or column passes through the colors you want. Smooth gradients, strong transitions, and low-noise images generally produce the best results.

## Color spaces

The Display P3 option rasterizes the source into Display P3 and declares **display-p3** in JSON. The sRGB option does the equivalent for sRGB.

This declaration is significant: Mandelbrot Metal 3.0 converts imported components from the declared source space into the app’s active rendering space. Do not relabel an existing palette without converting its RGB values.

## JSON schema

Photo2Palette 3.0 deliberately retains palette schema version 1:

~~~json
{
  "colorSpace": "display-p3",
  "name": "Your Palette",
  "schemaVersion": 1,
  "stops": [
    { "b": 0.3, "g": 0.2, "r": 0.1, "t": 0.0 },
    { "b": 0.6, "g": 0.5, "r": 0.4, "t": 1.0 }
  ],
  "type": "palette"
}
~~~

Mandelbrot Metal 3.0 validates the type, schema, color space, name, stop count, positions, and RGB ranges before importing.

The preferred single-palette filename suffix is **.mandelpalette.json**; bundles exported by the app use **.mandelpalettes.json**. Legacy plain JSON files remain discoverable through content sniffing.

## Requirements

- macOS
- Swift 5.7 or later
- No Xcode project is required

## Troubleshooting

- Run **photo2palette --version** to confirm the 3.0 utility is installed.
- If the app rejects a file, run the CLI again without manually editing its JSON metadata.
- If a palette samples the wrong region, crop the image or explicitly set the sampling axis.
- If colors look different from the source, verify that the selected CLI color space matches the intended workflow and that Mandelbrot Metal’s Wide Color setting is correct.

Contact: <https://mandelbrot-metal.com/contact>

Written by Michael Stebel

© 2026 Mandelbrot Metal. All rights reserved.
