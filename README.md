# photo2palette

`photo2palette` is a command-line tool that samples colors from an image and converts them into a palette for **Mandelbrot Metal**, either as:

- **Swift code** (`registerCustom(...)`) you can paste into the app, or  
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
  --format, -f           "swift" (default) or "json"

Adjustments:
  --sat <factor>         Saturation multiplier (default: 1.0)
  --gamma <value>        Gamma correction (default: 1.0)
  --stretch              Stretch luminance to 0–1
  --no-stretch           Disable luminance stretch

Other:
  --help, -h             Show help and exit
```

---

## Examples

### Swift output
```bash
photo2palette --image strip.png --name "Sunset" > Sunset.swift
```

### JSON output (importable)
```bash
photo2palette --image strip.png --name "Sunset" --format json > Sunset.palette.json
```

### 768-stop Ultra-Wide palette
```bash
photo2palette --image strip.png --name "Aurora UW" --steps 768 --format json > AuroraUW.palette.json
```

### Vertical sampling
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
