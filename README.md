# hyprsnip

A Bash script for context-aware screenshots on the **awesome** [Hyprland](https://hyprland.org/).<br>
Select any screen region and the screenshot is automatically named after the window it captured — then saved, copied to clipboard, or both, with an interactive desktop notification.<br>
Optionally, send the screenshot to the **Claude API** to convert it to plain text, HTML, or Markdown instead of saving the image.<br>
If you click the notification the screenshots directory will open.

## Features

- Area selection via `slurp`
- Automatic window title detection via `hyprctl`
- Timestamped filenames with sanitised window names (e.g. `screenshot_2024-03-15T14-30-05_Firefox.png`)
- Three modes: copy to clipboard, save to disk, or both
- **Text conversion mode** — send the screenshot to Claude and convert it to plain text, HTML, or Markdown, saved as `screenshot_data_{date}_{name}.{txt|html|md}`
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
| `curl` *(optional)* | Required for `--text` mode to call the Claude API |

Install on Arch-based systems:

If you already have [ml4w](https://github.com/mylinuxforwork/dotfiles) installed you won't need to install these.

```bash
sudo pacman -S slurp grim wl-clipboard jq libnotify nautilus
```

## Installation

```bash
git clone https://github.com/matsondawson/hyprsnip.git
cd hyprsnip
chmod +x hyprsnip.sh
```

Optionally, add it to your `$PATH`:

```bash
cp hyprsnip.sh ~/.local/bin/hyprsnip
```

## Usage

```
hyprsnip <mode> [OPTIONS]

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
  -t,  --text FORMAT     Send image to Claude and convert to text. FORMAT:
                           text   - plain text extraction  → .txt
                           html   - convert to HTML        → .html
                           markup - convert to Markdown    → .md
                         Saves/copies text output instead of the image.
                         Filename: screenshot_data_{date}_{name}.{ext}
                         Requires ANTHROPIC_API_KEY to be set.
  -nn, --no-notify       Suppress the desktop notification
  -v,  --verbose         Print extra info during execution
  -h,  --help            Show help and exit
```

### Examples

```bash
hyprsnip copy
hyprsnip save --output ~/Desktop/shots
hyprsnip copysave --explorer thunar --verbose
hyprsnip save --no-notify
hyprsnip copysave --area active
hyprsnip copysave --area screen
ANTHROPIC_API_KEY="sk-ant-..." hyprsnip copy --text text    # extract plain text, copy to clipboard
ANTHROPIC_API_KEY="sk-ant-..." hyprsnip save --text html    # convert to HTML, save as .html
ANTHROPIC_API_KEY="sk-ant-..." hyprsnip save --text markup  # convert to Markdown, save as .md
```

### Converting screenshots to text with Claude

The `--text` flag captures a screenshot and sends it to the [Claude API](https://www.anthropic.com/api) for conversion instead of saving or copying the image. Three output formats are supported:

| Format   | Output                  | Use case                                       |
|----------|-------------------------|------------------------------------------------|
| `text`   | Plain text (`.txt`)     | OCR, copying text from images, terminal output |
| `html`   | HTML fragment (`.html`) | Web content, tables, structured documents      |
| `markup` | Markdown (`.md`)        | Notes, documentation, README content           |

The filename is derived by Claude based on the content — e.g. a screenshot of a bash error becomes `screenshot_data_2024-03-15T14-30-05_bash_error_log.txt`.

Set your API key once in your shell config (e.g. `~/.config/fish/config.fish`):

```fish
set -x ANTHROPIC_API_KEY "sk-ant-..."
```

Then use it like any other mode:

```bash
hyprsnip copy --text text      # OCR an image, copy text to clipboard
hyprsnip save --text html      # convert a webpage screenshot to HTML
hyprsnip copysave --text markup  # convert notes/docs to Markdown, save + copy
```

### Hyprland keybind

Add to `~/.config/hypr/hyprland.conf`:

```ini
bind = , PRINT, exec, ~/.local/bin/hyprsnip copysave                           # Copy area to clipboard and also save to screen shots
bind = $mainMod, PRINT, exec, ~/.local/bin/hyprsnip copysave -a active         # Copy active window to clipboard and also save to screen shots
bind = $mainMod SHIFT, PRINT, exec, ~/.local/bin/hyprsnip copysave -a screen   # Copy active workspace to clipboard and also save to screen shots
```

## How It Works

1. The capture area is determined by `--area`: `select` (default) opens a `slurp` crosshair to drag a region; `active` captures the focused window's geometry via `hyprctl activewindow`; `screen` captures the entire focused monitor via `hyprctl monitors`.
2. `hyprctl activeworkspace` gets the current workspace ID.
3. `hyprctl clients` is queried to find the window whose bounding box contains the centre point of the selection. Its title becomes part of the filename.
4. `grim` captures the selected region.
5. If `--text FORMAT` is set, the PNG is base64-encoded and sent to the Claude API with a format-specific instruction. Claude converts the content to plain text, HTML, or Markdown and derives a short descriptive name. The result is saved as `screenshot_data_{date}_{name}.{ext}` and/or copied to clipboard.
6. Otherwise, the image is copied to clipboard via `wl-copy` and/or saved to disk.
7. A `notify-send` notification appears. If the output was saved, clicking the notification opens the screenshots folder in your configured file manager.

If no window is found at the centre of the selection (e.g. you captured the desktop background), the filename falls back to `Desktop`.

## License

MIT — see [LICENSE](https://mit-license.org/) for details.
