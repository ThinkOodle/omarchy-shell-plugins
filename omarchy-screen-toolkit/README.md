# omarchy-screen-toolkit

Screen-tools bar widget for `omarchy-shell`. Click the toolbar icon and pick a tool:

- **Color** — pixel color picker with HEX/RGB/HSL/HSV copy-buttons and a persistent history
- **Annotate** — region screenshot opened in the configured editor (defaults to `satty`)
- **Measure** — full-screen ruler overlay; drag to measure (Alt to constrain), pin multiple measurements, copy as `Wpx (W×H)`
- **Pin** — region screenshot floated on top of the desktop, draggable + resizable + copy-to-clipboard; multiple pins stack
- **Palette** — extract dominant colors from a region (ImageMagick) with history
- **OCR** — region text extraction via tesseract (`omarchy-capture-text-extraction`)
- **QR** — decode QR codes / barcodes via zbar with "Open" action for URLs
- **Lens** — reverse-image-search a region (uploads to a share host, opens the search URL)
- **Record** — MP4 region recording (toggle via `omarchy-capture-screenrecording`) or GIF
- **Mirror** — floating webcam preview with flip, aspect toggle, and camera switch

A fresh color pick opens a centered result overlay (ESC and outside-click dismiss it).
Subsequent picks join a "History" strip of circular swatches. The same machinery feeds
palette history. Both are stored inline in `~/.config/omarchy/shell.json`.

## Dependencies

Most of these ship by default on an Omarchy install. Anything not pre-installed is
called out below.

| Tool         | Used by                       | Notes |
|--------------|-------------------------------|-------|
| `slurp`      | every region tool             | already in Omarchy |
| `grim`       | every region tool             | already in Omarchy |
| `hyprpicker` | color pick, region freeze     | already in Omarchy |
| `wl-clipboard` (`wl-copy`) | every tool        | already in Omarchy |
| `tesseract`  | OCR                            | already in Omarchy (add language packs for non-English) |
| `jq`         | GIF / Lens scripts            | already in Omarchy |
| `curl`       | Lens upload                   | already in Omarchy |
| `magick` (ImageMagick) | Palette             | **add via** `sudo pacman -S imagemagick` |
| `zbarimg` (zbar)       | QR                  | **add via** `sudo pacman -S zbar` |
| `ffmpeg`     | GIF post-process               | already in Omarchy |
| `gifski`     | optional, higher-quality GIFs  | **add via** `sudo pacman -S gifski` (not required; current scripts use ffmpeg's palettegen) |
| `gpu-screen-recorder` | mp4 + GIF capture     | already in Omarchy |
| `wf-recorder` | optional alternative recorder | not required |

## Install

Symlink-from-checkout style, mirroring sibling plugins in this repo:

```bash
mkdir -p ~/.config/omarchy/plugins
ln -s ~/Code/omarchy-shell-plugins/omarchy-screen-toolkit \
      ~/.config/omarchy/plugins/omarchy-screen-toolkit
omarchy-shell shell setPluginEnabled omarchy-screen-toolkit true
omarchy restart shell
```

If a previous install exists, remove it first:

```bash
rm -rf ~/.config/omarchy/plugins/omarchy-screen-toolkit
```

`setPluginEnabled` appends `{ "id": "omarchy-screen-toolkit" }` to your
`shell.json` `bar.layout.right` section. Move the entry by hand if you want
the icon elsewhere in the bar.

## Settings

Open the toolbar popup, click the gear icon to flip into the settings tab.
Every field writes back into the same `shell.json` entry as inline keys.

| Key                          | Default                                                | Notes |
|------------------------------|--------------------------------------------------------|-------|
| `screenshotPath`             | `$XDG_PICTURES_DIR`                                    | currently informational; existing capture script owns the path |
| `videoPath`                  | `$XDG_VIDEOS_DIR`                                      | currently informational |
| `ocrLang`                    | `eng`                                                  | passed to tesseract via the existing OCR script |
| `recordFormat`               | `mp4`                                                  | `mp4` uses `omarchy-capture-screenrecording`; `gif` uses `bin/ost-record-gif` |
| `gifMaxSeconds`              | `30`                                                   | exposed to `ost-record-gif` via `OST_GIF_MAX_SECS` |
| `searchEngineUrl`            | `https://www.google.com/searchbyimage?image_url=`      | suffixed with the uploaded image URL |
| `copyRecordingToClipboard`   | off                                                    | passes through to the GIF script (mp4 path is owned by Omarchy) |
| `skipRecordingConfirmation`  | off                                                    | reserved |

The bundled scripts in `bin/` also accept these environment variables for ad-hoc
overrides without touching settings:

- `OST_PALETTE_N` — palette colour count (default 6)
- `OST_GIF_FPS` — GIF frame rate (default 15)
- `OST_GIF_MAX_SECS` — auto-stop duration (default 30)
- `OST_SHARE_HOST` — POST endpoint for Lens upload (default `https://0x0.st`)
- `OST_SEARCH_URL` — base URL prefix for Lens (default Google Images by URL)

## IPC

The bar widget registers an `omarchy-shell` IPC handler called `screen-toolkit`:

```bash
omarchy-shell screen-toolkit toggle
omarchy-shell screen-toolkit open
omarchy-shell screen-toolkit close
```

Bind to a Hyprland keybind for quick keyboard access.

## Files

```
omarchy-screen-toolkit/
├── manifest.json
├── BarWidget.qml      # bar icon + main popup + result overlay
├── Overlay.qml        # router that mounts pin / measure / mirror slots
├── bin/
│   ├── ost-color-pick
│   ├── ost-palette
│   ├── ost-qr
│   ├── ost-lens
│   ├── ost-pin-region
│   └── ost-record-gif
└── components/
    ├── Pin.qml        # floating image pin (per-slot, additive)
    ├── Measure.qml    # full-screen measurement overlay (singleton)
    └── Mirror.qml     # floating webcam mirror (singleton)
```

## Status

All ten tools are wired up. Pin / Measure / Mirror live in `components/`
and are mounted on demand by `Overlay.qml`; closing the last overlay
asks the shell to hide the plugin so the next IPC `toggle` opens cleanly.
