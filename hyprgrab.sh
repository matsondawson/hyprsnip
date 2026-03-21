#!/bin/bash

# ─── Defaults ────────────────────────────────────────────────────────────────
FILE_EXPLORER="nautilus"
SCREENSHOT_DIR="$HOME/Pictures/screenshots"
NOTIFY=true
VERBOSE=false
DATEFORMAT="+%Y-%m-%dT%H:%M:%S"

# ─── Help ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") <mode> [OPTIONS]

Copy and or save selected screen region, naming the file after the window it was copied from.

Modes:
  copy        Copy to clipboard
  copysave    Copy to clipboard, and save to disk
  save        Save to disk only

Options:
  -d, --dir DIR          Directory to save screenshots (default: ~/Pictures/screenshots)
                         (only relevant for 'copysave' and 'save' modes)
  -f, --date-format      File date prefix format. (default: ${DATEFORMAT})
  -e, --explorer APP     File explorer to open on notification click (default: nautilus)
  -n, --no-notify        Suppress the desktop notification
  -v, --verbose          Print extra info during execution
  -h, --help             Show this help message and exit

Examples:
  $(basename "$0") copy
  $(basename "$0") save --dir ~/Desktop/shots
  $(basename "$0") copysave --explorer thunar --verbose
  $(basename "$0") save --no-notify
EOF
}

# ─── Argument Parsing ─────────────────────────────────────────────────────────

# Require at least one argument
if [[ $# -eq 0 ]]; then
    echo "$(basename "$0"): missing mode argument" >&2
    usage && exit 1
fi

# Check for help before anything else
for arg in "$@"; do
    [[ "$arg" == "-h" || "$arg" == "--help" ]] && usage && exit 0
done

# First positional argument is the mode
MODE="$1"
shift

case "$MODE" in
    copy|copysave|save) ;;
    *)
        echo "Error: invalid mode '$MODE'. Must be one of: copy, copysave, save." >&2
        echo "Run '$(basename "$0") --help' for usage." >&2
        exit 1
        ;;
esac

# Derive COPY / SAVE behaviour from mode
case "$MODE" in
    copy)     DO_COPY=true;  DO_SAVE=false ;;
    copysave) DO_COPY=true;  DO_SAVE=true  ;;
    save)     DO_COPY=false; DO_SAVE=true  ;;
esac

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir)
            SCREENSHOT_DIR="$2"
            shift 2
            ;;
        -f|--date-format)
            DATEFORMAT="$2"
            shift 2
            ;;
        -e|--explorer)
            FILE_EXPLORER="$2"
            shift 2
            ;;
        -n|--no-notify)
            NOTIFY=false
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Run '$(basename "$0") --help' for usage." >&2
            exit 1
            ;;
    esac
done

# ─── Helpers ──────────────────────────────────────────────────────────────────
log() { $VERBOSE && echo "[INFO] $*"; }

# ─── Ensure output directory exists (only when saving) ───────────────────────
if $DO_SAVE; then
    mkdir -p "$SCREENSHOT_DIR" || { echo "Failed to create directory: $SCREENSHOT_DIR" >&2; exit 1; }
fi

# ─── 1. Area selection ────────────────────────────────────────────────────────
log "Waiting for area selection..."
AREA=$(slurp)
[ -z "$AREA" ] && { log "Selection cancelled."; exit 1; }
log "Selected area: $AREA"

# ─── 2. Active workspace ──────────────────────────────────────────────────────
WS_ID=$(hyprctl activeworkspace -j | jq '.id')
log "Workspace ID: $WS_ID"

# ─── 3. Parse coordinates ─────────────────────────────────────────────────────
X=$(echo "$AREA" | cut -d',' -f1)
Y=$(echo "$AREA" | cut -d',' -f2 | cut -d' ' -f1)
W=$(echo "$AREA" | cut -d' ' -f2 | cut -d'x' -f1)
H=$(echo "$AREA" | cut -d' ' -f2 | cut -d'x' -f2)

CENTER_X=$((X + W/2))
CENTER_Y=$((Y + H/2))
log "Center point: ${CENTER_X},${CENTER_Y}"

# ─── 4. Detect window under selection ────────────────────────────────────────
WINDOW_TITLE=$(hyprctl clients -j | jq -r ".[] |
    select(.workspace.id == $WS_ID and .hidden == false and .mapped == true and
           .at[0] <= $CENTER_X and .at[0] + .size[0] >= $CENTER_X and
           .at[1] <= $CENTER_Y and .at[1] + .size[1] >= $CENTER_Y) | .title" | head -n 1)

[ -z "$WINDOW_TITLE" ] && WINDOW_TITLE="Desktop"
log "Window title: $WINDOW_TITLE"

# ─── 5. Build filename ────────────────────────────────────────────────────────
ISO_DATE=$(date "$DATEFORMAT" | tr ':' '-')
CLEAN_NAME=$(echo "$WINDOW_TITLE" | tr -dc '[:alnum:]\n\r ' | tr ' ' '_')

if $DO_SAVE; then
    SUBFILENAME="screenshot_${ISO_DATE}_${CLEAN_NAME}.png"
    FILENAME="$SCREENSHOT_DIR/$SUBFILENAME"
    TMPFILE=""
else
    TMPFILE=$(mktemp /tmp/screenshot_XXXXXX.png)
    FILENAME="$TMPFILE"
fi
log "Output file: $FILENAME"

# ─── 6. Capture ───────────────────────────────────────────────────────────────
grim -g "$AREA" "$FILENAME" || { echo "grim failed to capture screenshot." >&2; exit 1; }
log "Screenshot captured."

# ─── 7. Copy to clipboard ─────────────────────────────────────────────────────
if $DO_COPY; then
    wl-copy < "$FILENAME"
    log "Copied to clipboard."
fi

# ─── Clean up temp file (copy-only mode) ──────────────────────────────────────
if [[ -n "$TMPFILE" ]]; then
    rm -f "$TMPFILE"
    log "Temp file removed."
fi

# ─── 8. Notification ──────────────────────────────────────────────────────────
if $NOTIFY; then
    log "Notifying"

    MESSAGE="Screenshot saved to:"
    if $DO_COPY && $DO_SAVE; then
      MESSAGE="Screenshot copied & saved to:"
    fi

    ACTION=""
    if $DO_SAVE; then
      ACTION=$(notify-send "$MESSAGE" "${SUBFILENAME:0:48}" \
          -i "${FILENAME:-utilities-screenshot}" \
          --action="default=Open Folder" \
          --hint=int:transient:1
          )
    else
      ACTION=$(notify-send "Screenshot Copied")
    fi

    if $DO_SAVE && [ "$ACTION" = "default" ]; then
      log "Opening $SCREENSHOT_DIR in $FILE_EXPLORER"
      $FILE_EXPLORER -w "$SCREENSHOT_DIR" &
    fi
fi

exit 0