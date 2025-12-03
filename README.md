# photo2palette

`photo2palette` is a command-line tool that samples colors from an image and converts them into a palette for **Mandelbrot Metal**, either as:

- **Swift code** (`registerCustom(...)`) not for users, or  
- **A JSON palette file** that imports directly via *Manage Palettes → Import…*

It supports horizontal or vertical sampling, configurable step counts (including 768-step Ultra-Wide palettes), and optional color adjustments.

---

## Installation

1. Save the script as `photo2palette.swift`  
2. Make it executable:

   ```bash
   chmod +x photo2palette.swift
   ```

3. Run it locally:

   ```bash
   ./photo2palette.swift --help
   ```

4. (Optional) Install globally:

   ```bash
   sudo cp photo2palette.swift /usr/local/bin/photo2palette
   ```

---

## Usage / CLI Help

```text
Usage:
  photo2palette --image <path> [options]

Required:
  --image, -i <path>     Input image path

Options:
  --name, -n <name>      Palette name (default: "Imported Palette")
  --steps, -s <N>        Number of stops (default: 512)
  --vertical             Sample a vertical column (default: horizontal row)
  --format, -f           "swift" (default) or "json" (users MUST select json)

Adjustments:
  --sat <factor>         Saturation multiplier (default: 1.0)
  --gamma <value>        Gamma correction (default: 1.0)
  --stretch              Stretch luminance to 0–1
  --no-stretch           Disable luminance stretch

Other:
  --help, -h             Show help and exit
```

---

## Choosing & Preparing Source Images

Creating a great Mandelbrot Metal palette starts with choosing the right source image. Because Photo2Palette extracts a continuous sequence of sampled colors, the quality and structure of the image directly affect the smoothness, contrast, and visual character of the resulting palette. Here are some guidelines to help you get the best results.

### 1. Choose Images With Strong Color Structure
Palettes work best when the source image has:
- Clear gradients or transitions  
- Distinct color regions  
- Good separation between dark, mid, and highlight tones  
- Minimal noise or compression artifacts

**Great candidates:**
- Sunset/sunrise photos  
- Macro shots with continuous shading  
- Abstract digital art  
- Clean gradients or nebula-style images  

**Less ideal:**
- Highly detailed scenes with random textures  
- Photos dominated by a single flat color  
- Grainy low-light images

### 2. Prefer Horizontal Gradients
Photo2Palette samples the image horizontally (left → right) or vertically depending on your settings, but a **horizontal gradient** gives the most intuitive and predictable results.

If your image has a natural gradient direction, orient it so the transition runs along the axis you plan to sample.

### 3. Crop Strategically
Cropping can dramatically improve palette quality.

You should crop when:
- Only one region of the image contains the gradient you want  
- The full image contains distracting colors you *don’t* want  
- You want to isolate a smooth transition from a noisy background  

**Best practice:**
- Crop to a thin horizontal strip that contains the precise gradient you want sampled  
- Avoid large areas of flat/solid color unless that’s intentional  
- Remove shadows, dark corners, or lens vignetting that could skew the gradient

### 4. Use High-Resolution Images
Higher resolution gives:
- Smoother sampling  
- Cleaner gradients  
- More subtle color transitions  

Low-res images can produce:
- Banding  
- Unwanted jumps in color  
- Repeated blocks of similar tones  

A width of **at least 1024px** is recommended for ultra-wide palettes.

### 5. Avoid Extreme Dynamic Range (Unless Intended)
Very dark shadows or clipped highlights can lead to:
- Abrupt ramps  
- Long stretches of black or white  
- Harsh jumps in color  

If an image has very deep shadows or extremely bright areas:
- Crop them out  
- Or lightly edit the image to compress extremes before sampling  

### 6. Pre-Process If Needed
If you want very fine control, simple image edits help:
- Slight blur → smooths noise and texture  
- Curves adjustment → enhances contrast in the range you care about  
- Color grading → shifts the palette into a desired mood  

This is optional, but useful for dialed-in control.

### 7. Test & Iterate
Because Photo2Palette outputs a fully importable `.json` file, you can:
- Import multiple variants into Mandelbrot Metal  
- Compare them using the palette picker  
- Keep the best one or adjust your crop/image and run again  

Tweaking just the crop or rotation of the source image often yields dramatically different palettes — experimenting is part of the fun.

---

## Examples


### JSON output (importable)
```bash
photo2palette --image strip.png --name "Sunset" --format json > Sunset.palette.json
```

### 768-stop Ultra-Wide palette (importable)
```bash
photo2palette --image strip.png --name "Aurora UW" --steps 768 --format json > AuroraUW.palette.json
```

### Vertical sampling (importable)
```bash
photo2palette --image vertical_strip.png --vertical --name "Vertical" --format json > Vertical.palette.json
```

---

## JSON Schema

```json
{
  "colorSpace": "display-p3",
  "name": "Your Palette",
  "schemaVersion": 1,
  "stops": [
    { "r": 0.123, "g": 0.456, "b": 0.789, "t": 0.0000 }
  ]
}
```

---

## Requirements

- macOS, Swift 5.7+
- No Xcode needed

---

## Troubleshooting

If you experience any issues using this with Mandelbrot Metal's Manage Palettes, please let me know at https://mandelbrot-metal.com/contact.

Written by Michael Stebel

© 2025 Mandelbrot Metal - All Rights Reserved.
