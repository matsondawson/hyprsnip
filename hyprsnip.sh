#!/bin/bash

# ─── Defaults ────────────────────────────────────────────────────────────────
FILE_EXPLORER="nautilus"
SCREENSHOT_DIR="$HOME/Pictures/screenshots"
NOTIFY=true
VERBOSE=false
AREA_MODE="select"
DATEFORMAT="+%Y-%m-%dT%H:%M:%S"
TEXT_FORMAT=""  # text | html | markup

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
  -t,  --text FORMAT     Send image to Claude and convert to text. FORMAT must be:
                           text   - plain text extraction         → .txt
                           html   - convert to HTML               → .html
                           markup - convert to Markdown           → .md
                         Saves/copies the text output instead of the image.
                         Filename becomes screenshot_data_{date}_{derived_name}.{ext}
                         Requires ANTHROPIC_API_KEY to be set.
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
        -t|--text)
            case "$2" in
                text|html|markup) TEXT_FORMAT="$2" ;;
                *)
                    echo "Error: -t requires a format: text, html, or markup." >&2
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

if [[ -n "$TEXT_FORMAT" ]]; then
    # Always capture to a temp PNG; final text file determined after API call
    TMPFILE=$(mktemp /tmp/screenshot_XXXXXX.png)
    FILENAME="$TMPFILE"
elif $DO_SAVE; then
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


# ─── Text extraction via Claude API ───────────────────────────────────────
if [[ -n "$TEXT_FORMAT" ]]; then
    [[ -z "$ANTHROPIC_API_KEY" ]] && err "ANTHROPIC_API_KEY is not set."

    case "$TEXT_FORMAT" in
        text)
            TEXT_EXT="txt"
            FORMAT_INSTRUCTION="Extract all text from this image as plain text, preserving layout and structure."
            ;;
        html)
            TEXT_EXT="html"
            FORMAT_INSTRUCTION="Convert the content of this image to well-formed HTML. Use semantic tags. Do not include <html>/<head>/<body> wrappers — output a fragment only."
            ;;
        markup)
            TEXT_EXT="md"
            FORMAT_INSTRUCTION="Convert the content of this image to Markdown. Preserve headings, lists, code blocks, tables, and emphasis where appropriate."
            ;;
    esac

    log "Encoding image and calling Claude API (format: $TEXT_FORMAT)..."
    B64_TMPFILE=$(mktemp /tmp/hyprsnip_b64_XXXXXX)
    trap '[[ -n "$TMPFILE" ]] && rm -f "$TMPFILE"; [[ -n "$B64_TMPFILE" ]] && rm -f "$B64_TMPFILE"' EXIT
    base64 -w 0 "$FILENAME" > "$B64_TMPFILE"

    API_RESPONSE=$(jq -n \
        --rawfile b64 "$B64_TMPFILE" \
        --arg instruction "$FORMAT_INSTRUCTION" \
        '{
            model: "claude-sonnet-4-6",
            max_tokens: 4096,
            messages: [{
                role: "user",
                content: [
                    {
                        type: "image",
                        source: { type: "base64", media_type: "image/png", data: ($b64 | rtrimstr("\n")) }
                    },
                    {
                        type: "text",
                        text: ("Respond with raw JSON only — no markdown, no code fences, no explanation. The JSON object must have exactly two fields: \"name\" (a concise snake_case identifier, max 30 chars, derived from the content — e.g. meeting_notes, error_log, code_snippet) and \"text\" (the converted content). " + $instruction)
                    }
                ]
            }]
        }' \
        | curl -s https://api.anthropic.com/v1/messages \
            -H "x-api-key: $ANTHROPIC_API_KEY" \
            -H "anthropic-version: 2023-06-01" \
            -H "content-type: application/json" \
            -d @-)

    CLAUDE_JSON=$(echo "$API_RESPONSE" | jq -r '.content[0].text' | sed '/^```/d')
    DERIVED_NAME=$(echo "$CLAUDE_JSON" | jq -r '.name' | tr -dc '[:alnum:]_' | cut -c1-30)
    TEXT_CONTENT=$(echo "$CLAUDE_JSON" | jq -r '.text')

    [[ -z "$DERIVED_NAME" || "$DERIVED_NAME" == "null" ]] && err "Claude did not return a valid name. API response: $API_RESPONSE"
    [[ -z "$TEXT_CONTENT" || "$TEXT_CONTENT" == "null" ]] && err "Claude did not return text content. API response: $API_RESPONSE"

    log "Derived name: $DERIVED_NAME"

    if $DO_SAVE; then
        SUBFILENAME="screenshot_data_${ISO_DATE}_${DERIVED_NAME}.${TEXT_EXT}"
        TEXT_FILE="$SCREENSHOT_DIR/$SUBFILENAME"
        printf '%s' "$TEXT_CONTENT" > "$TEXT_FILE" || err "Failed to write text file."
        log "Text saved to: $TEXT_FILE"
    fi

    if $DO_COPY; then
        printf '%s' "$TEXT_CONTENT" | wl-copy
        log "Text copied to clipboard."
    fi

    if $NOTIFY; then
        if $DO_SAVE; then
            MESSAGE="Converted to ${TEXT_FORMAT} & saved to:"
            $DO_COPY && MESSAGE="Converted to ${TEXT_FORMAT}, copied & saved to:"
            ACTION_RESULT=$(notify-send "$MESSAGE" "${SUBFILENAME:0:48}" \
                --hint=int:transient:1 \
                --action="default=Open Folder")
            [ "$ACTION_RESULT" = "default" ] && setsid "$FILE_EXPLORER" "$SCREENSHOT_DIR" > /dev/null 2>&1 &
        else
            notify-send "Converted to ${TEXT_FORMAT} & copied" --hint=int:transient:1
        fi
    fi

    exit 0
fi

# ─── Copy to clipboard ─────────────────────────────────────────────────────
if $DO_COPY; then
    wl-copy < "$FILENAME"
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