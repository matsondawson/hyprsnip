#!/bin/bash

# ─── Defaults ────────────────────────────────────────────────────────────────
FILE_EXPLORER="nautilus"
SCREENSHOT_DIR="$HOME/Pictures/screenshots"
NOTIFY=true
VERBOSE=false
AREA_MODE="select"
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
  -o, --output DIR       Directory to save screenshots (default: ~/Pictures/screenshots)
                         (only relevant for 'copysave' and 'save' modes)
  -df, --date-format     File date prefix format. (default: ${DATEFORMAT})
  -e,  --explorer APP    File explorer to open on notification click (default: nautilus)
  -a,  --area            select - Select an area (default)
                         active - Active window
                         screen - Whole screen
  -nn, --no-notify       Suppress the desktop notification
  -v,  --verbose         Print extra info during execution
  -h,  --help            Show this help message and exit

Examples:
  $(basename "$0") copy
  $(basename "$0") save --output ~/Desktop/shots
  $(basename "$0") copysave --explorer thunar --verbose
  $(basename "$0") save --no-notify
  $(basename "$0") copysave --area active
  $(basename "$0") copysave --area screen
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
        -o|--output)
            SCREENSHOT_DIR="$2"
            shift 2
            ;;
        -df|--date-format)
            DATEFORMAT="$2"
            shift 2
            ;;
        -e|--explorer)
            FILE_EXPLORER="$2"
            shift 2
            ;;
        -a|--area)
            case "$2" in
                select|active|screen) AREA_MODE="$2" ;;
                *)
                    echo "Error: invalid area mode '$2'. Must be one of: select, active, screen." >&2
                    echo "Run '$(basename "$0") --help' for usage." >&2
                    exit 1
                    ;;
            esac
            shift 2
            ;;
        -nn|--no-notify)
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
log() {
  $VERBOSE && echo "[INFO] $*";
}

err() {
  echo "[ERROR] $*" >&2;
  notify-send "Screenshot Error" "$*" -i dialog-error --hint=int:transient:1;
  exit 1;
}

# ─── Ensure output directory exists (only when saving) ───────────────────────
if $DO_SAVE; then
    mkdir -p "$SCREENSHOT_DIR" || err "Failed to create directory: $SCREENSHOT_DIR";
fi

WS_ID=$(hyprctl activeworkspace -j | jq '.id')
log "Workspace ID: $WS_ID"

# ─── Area selection ────────────────────────────────────────────────────────
case "$AREA_MODE" in
    select)
        log "Waiting for area selection..."
        AREA=$(slurp)
        [ -z "$AREA" ] && { log "Selection cancelled."; exit 1; }
        log "Selected area: $AREA"
        ;;
    active)
        log "Capturing active window..."
        WINDOW_JSON=$(hyprctl activewindow -j)
        WINDOW_TITLE=$(echo "$WINDOW_JSON" | jq -r '.title')
        AREA=$(echo "$WINDOW_JSON" | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
        [ -z "$AREA" ] && err "Could not determine active window geometry."
        log "Active window area: $AREA"
        ;;
    screen)
        log "Capturing active workspace..."
        AREA=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | "\(.x),\(.y) \(.width)x\(.height)"')
        [ -z "$AREA" ] && err "Could not determine active monitor geometry."
        log "Active monitor area: $AREA"
        WORKSPACE_WINDOWS=$(hyprctl clients -j | jq -r "[.[] | select(.workspace.id == $WS_ID and .hidden == false and .mapped == true)]")
        WINDOW_COUNT=$(echo "$WORKSPACE_WINDOWS" | jq 'length')
        if [[ "$WINDOW_COUNT" -eq 1 ]]; then
            WINDOW_TITLE=$(echo "$WORKSPACE_WINDOWS" | jq -r '.[0].title')
            log "Single window on workspace, using title: $WINDOW_TITLE"
        else
            WINDOW_TITLE="workspace_${WS_ID}"
            log "Multiple windows on workspace ($WINDOW_COUNT), using: $WINDOW_TITLE"
        fi
        ;;
esac

# ─── Detect window under selection ────────────────────────────────────────
if [[ "$AREA_MODE" == "select" ]]; then
  # Parse coordinates
  X=$(echo "$AREA" | cut -d',' -f1)
  Y=$(echo "$AREA" | cut -d',' -f2 | cut -d' ' -f1)
  W=$(echo "$AREA" | cut -d' ' -f2 | cut -d'x' -f1)
  H=$(echo "$AREA" | cut -d' ' -f2 | cut -d'x' -f2)

  CENTER_X=$((X + W/2))
  CENTER_Y=$((Y + H/2))
  log "Center point: ${CENTER_X},${CENTER_Y}"

  WINDOW_TITLE=$(hyprctl clients -j | jq -r "
    [.[] | select(
        .workspace.id == $WS_ID and
        .hidden == false and
        .mapped == true and
        .at[0] <= $CENTER_X and .at[0] + .size[0] >= $CENTER_X and
        .at[1] <= $CENTER_Y and .at[1] + .size[1] >= $CENTER_Y
    )] |
    sort_by(if .floating then 0 else 1 end) |
    .[0].title")
fi

[[ "$WINDOW_TITLE" == "null" || -z "$WINDOW_TITLE" ]] && WINDOW_TITLE="Desktop"
log "Window title: $WINDOW_TITLE"

# ─── Build filename ────────────────────────────────────────────────────────
# Get date and convert :'s in time to -'s as : aren't valid in filenames
ISO_DATE=$(date "$DATEFORMAT" | tr ':/<>\\|?* ' '-')
CLEAN_NAME=$(echo "$WINDOW_TITLE" | tr -dc '[:alnum:]_\n\r ' | tr ' ' '_')

if $DO_SAVE; then
    SUBFILENAME="screenshot_${ISO_DATE}_${CLEAN_NAME}.png"
    FILENAME="$SCREENSHOT_DIR/$SUBFILENAME"
    TMPFILE=""
else
    TMPFILE=$(mktemp /tmp/screenshot_XXXXXX.png)
    FILENAME="$TMPFILE"
fi
log "Output file: $FILENAME"

# ─── Clean up temp file (copy-only mode) ──────────────────────────────────────
trap '[[ -n "$TMPFILE" ]] && rm -f "$TMPFILE"' EXIT

# ─── Capture ───────────────────────────────────────────────────────────────
grim -g "$AREA" "$FILENAME" || err "grim failed to capture screenshot."
log "Screenshot captured."

# ─── Copy to clipboard ─────────────────────────────────────────────────────
if $DO_COPY; then
    cat "$FILENAME" | wl-copy
    log "Copied to clipboard."
fi

# ─── Notification ──────────────────────────────────────────────────────────
if $NOTIFY; then
    log "Notifying"

    if $DO_SAVE; then
      MESSAGE="Screenshot saved to:"
      if $DO_COPY && $DO_SAVE; then
        MESSAGE="Screenshot copied & saved to:"
      fi

      ACTION_RESULT=$(notify-send "$MESSAGE" "${SUBFILENAME:0:48}" \
          -i "${FILENAME:-utilities-screenshot}" \
          --action="default=Open Folder" \
          --hint=int:transient:1
          )
    else
      ACTION_RESULT=$(notify-send "Screenshot copied" --hint=int:transient:1)
    fi

    if $DO_SAVE && [ "$ACTION_RESULT" = "default" ]; then
      log "Opening $SCREENSHOT_DIR in $FILE_EXPLORER"
      # Detach file explorer from original script process
      setsid "$FILE_EXPLORER" "$SCREENSHOT_DIR" > /dev/null 2>&1 &
    fi
fi