# Compact Pascal — Logo & Visual Identity

## Concept

The logo is a monochrome wireframe 3D surface plot of a damped cosine ripple function, evoking the mathematical heritage of Blaise Pascal. The visual language draws from 1970s computer science textbooks — warm, muted tones on cream stock.

The surface function is:

```
z(u, v) = cos(r) · e^(−0.3r)    where r = 4 · √(u² + v²)
```

Rendered as a wireframe mesh with depth-based opacity (far lines fade, near lines are opaque). Viewing angle: elevation −53°, azimuth 74°.

## Color Palette

| Role          | Name        | Hex       | RGB             | Usage                              |
|---------------|-------------|-----------|-----------------|-------------------------------------|
| Background    | Cream       | `#f5f0e0` | 245, 240, 224   | Icon/image backgrounds (top)        |
| Background    | Cream Dark  | `#ebd4d2` | 235, 228, 210   | Gradient endpoint (bottom)          |
| Wireframe     | Sienna      | `#6b3a2a` | 107, 58, 42     | Surface lines, bounding box         |
| Text band     | Deep Teal   | `#1a5c5a` | 26, 92, 90      | Horizontal band behind text         |
| Band text     | Light Cream | `#f0ead0` | 240, 234, 208   | "Compact Pascal" text on teal band  |
| Fine details  | Warm Black  | `#2a2a24` | 42, 42, 36      | Small text, captions (if needed)    |

The background is a subtle linear gradient from Cream (top) to Cream Dark (bottom).

## Typography

**Typeface:** Fira Sans (Google Fonts, SIL Open Font License)

- Text band: Fira Sans **700 (Bold)**, right-aligned
- Text size scales proportionally with the icon (≈5.5% of icon height)
- Band padding: 25% of text height above and below

## Logo Construction

### Icon (with text band)

Square format. Three sizes: 256×256, 128×128, 64×64.

```
+----------------------------------+
|                                  |
|     Wireframe surface            |
|     (clipped to icon bounds,     |
|      large enough to bleed       |  ← Surface centered at 40% height
|      past edges)                 |
|                                  |
|     ┌─ teal band ─────────────┐ |  ← Band at ~84% from top
|     │        Compact Pascal   │ |  ← Right-aligned, bold
|     └─────────────────────────┘ |
|                                  |  ← ~8% cream below band
+----------------------------------+
```

- No outer border
- Wireframe projection scale: ≈51% of icon size
- Grid density: 24 (256px), 20 (128px), 16 (64px)
- Stroke weight: 1.0 (256px), 0.8 (128px), 0.7 (64px)
- Text band sits at approximately 84% from top, leaving ~8% cream below
- The band overlaps the lower portion of the wireframe

### README Image (no text band)

400×400 px (rendered at 2× for retina). Wireframe surface only — no text band, no bounding box. Used with `<img width="400">` in the README.

### White Paper Cover (with bounding box)

800×800 SVG viewBox (vector, resolution-independent). Also available as 2400×2400 PNG.

- Includes bounding box with dashed back edges and solid front edges
- Back edges: 30% opacity, stroke-dasharray `4.8 4`
- Front edges: 55% opacity, solid
- Grid density: 48
- Surface centered at 47% height

## Asset Inventory

| File | Format | Size | Usage |
|------|--------|------|-------|
| `compact-pascal-icon-256.png` | PNG @2× | 256×256 | Primary icon, social media, documentation |
| `compact-pascal-icon-128.png` | PNG @2× | 128×128 | Smaller icon contexts |
| `compact-pascal-icon-64.png`  | PNG @2× | 64×64   | Favicon, small UI elements |
| `compact-pascal-readme.png`   | PNG @2× | 400×400 | GitHub README |
| `compact-pascal-cover.svg`    | SVG     | 800×800 | White paper cover (Typst/print) |
| `compact-pascal-cover.png`    | PNG @2× | 1200×1200 | Raster fallback for cover |

## Generator Tools

| File | Purpose |
|------|---------|
| `generate-assets.html`    | Opens in browser, renders all PNG assets with download buttons |
| `generate-cover-svg.js`   | Node.js script: `node generate-cover-svg.js > cover.svg` |
| `viewer.html`             | Interactive explorer with adjustable parameters |

## Usage Rules

- **Do not** place the logo on busy or dark backgrounds. Use cream or white.
- **Do not** add drop shadows, bevels, or other effects.
- **Do not** change the wireframe color or text band color.
- **Do not** rearrange the text band position or alignment.
- **Minimum display size:** 64×64 px for the icon with text band.
- The wireframe-only version (no text band) may be used at any size.
- The SVG cover image should be used for print whenever possible.
