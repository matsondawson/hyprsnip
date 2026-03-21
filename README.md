# hyprgrab

A Bash script for context-aware screenshots on [Hyprland](https://hyprland.org/). Select any screen region and the screenshot is automatically named after the window it captured — then saved, copied to clipboard, or both, with an interactive desktop notification.<br>
If you click the notification the screenshots directory will open.

## Features

- Area selection via `slurp`
- Automatic window title detection via `hyprctl`
- Timestamped filenames with sanitised window names (e.g. `screenshot_2024-03-15T14-30-05_Firefox.png`)
- Three modes: copy to clipboard, save to disk, or both
- Interactive notification — click to open the screenshots folder in your file manager
- Configurable save directory, date format, file explorer, and verbosity via CLI flags

## Dependencies

| Tool | Purpose |
|------|---------|
| [`slurp`](https://github.com/emersion/slurp) | Area selection |
| [`grim`](https://git.sr.ht/~emersion/grim) | Wayland screenshot capture |
| [`wl-copy`](https://github.com/bugaevc/wl-clipboard) | Clipboard integration |
| [`hyprctl`](https://wiki.hyprland.org/Configuring/Using-hyprctl/) | Active workspace & window info |
| [`jq`](https://stedolan.github.io/jq/) | JSON parsing |
| [`notify-send`](https://libnotify.gitlab.io/libnotify/) | Desktop notifications |
| `nautilus` *(optional)* | Opens the screenshots folder on notification click |

Install on Arch-based systems:

```bash
sudo pacman -S slurp grim wl-clipboard jq libnotify nautilus
```

## Installation

```bash
git clone https://github.com/your-username/hyprgrab.git
cd hyprgrab
chmod +x hyprgrab.sh
```

Optionally, add it to your `$PATH`:

```bash
cp hyprgrab.sh ~/.local/bin/hyprgrab
```

## Usage

```
hyprgrab <mode> [OPTIONS]

Modes:
  copy        Copy screenshot to clipboard only
  copysave    Copy to clipboard and save to disk
  save        Save to disk only

Options:
  -o, --output DIR       Directory to save screenshots (default: ~/Pictures/screenshots)
  -df, --date-format FMT Date prefix format (default: +%Y-%m-%dT%H:%M:%S)
  -e,  --explorer APP    File explorer for notification click (default: nautilus)
  -a,  --area            select - Select an area (default)
                         active - Active window
                         screen - Whole screen
  -nn, --no-notify       Suppress the desktop notification
  -v,  --verbose         Print extra info during execution
  -h,  --help            Show help and exit
```

### Examples

```bash
hyprgrab copy
hyprgrab save --output ~/Desktop/shots
hyprgrab copysave --explorer thunar --verbose
hyprgrab save --no-notify
hyprgrab copysave --area active
hyprgrab copysave --area screen
```

### Hyprland keybind

Add to `~/.config/hypr/hyprland.conf`:

```ini
bind = , Print, exec, ~/.local/bin/hyprgrab copysave
```

## How It Works

1. The capture area is determined by `--area`: `select` (default) opens a `slurp` crosshair to drag a region; `active` captures the focused window's geometry via `hyprctl activewindow`; `screen` captures the entire focused monitor via `hyprctl monitors`.
2. `hyprctl activeworkspace` gets the current workspace ID.
3. `hyprctl clients` is queried to find the window whose bounding box contains the centre point of the selection. Its title becomes part of the filename.
4. `grim` captures the selected region.
5. Depending on the mode, the image is copied to clipboard via `wl-copy` and/or saved to disk.
6. A `notify-send` notification appears. If the screenshot was saved, clicking the notification opens the screenshots folder in your configured file manager.

If no window is found at the centre of the selection (e.g. you captured the desktop background), the filename falls back to `Desktop`.

## License

MIT — see [LICENSE](https://mit-license.org/) for details.
