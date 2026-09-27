#!/usr/bin/env bash
# Installer for urdu-translit.
#
# Installs ./urdu-translit and your corrections, then checks dependencies.
# Two modes, remembered between runs so a re-run never silently changes
# layout back:
#
#   copy (default)  ~/.local/bin/urdu-translit is a real file, so the tool
#                   keeps working even if this project directory is moved or
#                   deleted. Corrections are copied once and left alone.
#   link (--link)   both are symlinks to this project, so edits here take
#                   effect immediately and there is only ever one copy.
#
# Usage: ./install.sh [--copy | --link] [--force-overrides]
#   --copy             install real files (use if you move this directory)
#   --link             symlink the script and corrections to this project
#   --force-overrides  in copy mode, overwrite an existing overrides.json
#                      (backs it up to overrides.json.bak first)
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SRC_DIR}/urdu-translit"
DEST="${HOME}/.local/bin/urdu-translit"

# The script reads overrides from XDG_CONFIG_HOME, so honour the same
# variable here rather than assuming ~/.config.
CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/urdu-translit"
OVERRIDES_SRC="${SRC_DIR}/overrides.json"
OVERRIDES_DEST="${CONFIG_DIR}/overrides.json"
MODE_FILE="${CONFIG_DIR}/install-mode"

# --- arguments ---
want_copy=0
want_link=0
force_overrides=0
for arg in "$@"; do
    case "$arg" in
        --copy) want_copy=1 ;;
        --link) want_link=1 ;;
        --force-overrides) force_overrides=1 ;;
        -h|--help)
            sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            echo "error: unknown option '$arg' (try --help)" >&2
            exit 2 ;;
    esac
done
if [[ "$want_copy" -eq 1 && "$want_link" -eq 1 ]]; then
    echo "error: --copy and --link are mutually exclusive" >&2
    exit 2
fi

if [[ ! -f "$SRC" ]]; then
    echo "error: $SRC not found (run from the project directory)" >&2
    exit 1
fi

# --- resolve the mode (flag > remembered > copy) ---
mode="copy"
if [[ -f "$MODE_FILE" ]]; then
    remembered="$(tr -d '[:space:]' < "$MODE_FILE")"
    case "$remembered" in
        copy|link) mode="$remembered" ;;
        *) echo "warn: ignoring unusable install-mode value '$remembered'" ;;
    esac
fi
if [[ "$want_link" -eq 1 ]]; then
    mode="link"
elif [[ "$want_copy" -eq 1 ]]; then
    mode="copy"
fi

# Point $1 at $2 as a symlink, idempotently and without ever destroying
# something the user has. Returns 0 on success.
make_link() {
    local dest="$1" src="$2" what="$3"
    mkdir -p "$(dirname "$dest")"
    if [[ -L "$dest" && "$(readlink -f "$dest" 2>/dev/null)" == "$(readlink -f "$src")" ]]; then
        echo "ok: ${what} already symlinked to this project"
        return 0
    fi
    if [[ -e "$dest" || -L "$dest" ]]; then
        # Keep whatever is there before replacing it. For overrides that
        # file may hold words that exist nowhere else; for the script it may
        # hold local edits. Either way, do not throw it away silently.
        if [[ -f "$dest" ]] && ! cmp -s "$src" "$dest"; then
            cp -a "$dest" "${dest}.bak"
            echo "     existing ${what} differed; saved to ${dest}.bak"
        fi
        rm -f "$dest"
    fi
    ln -s "$src" "$dest"
    echo "ok: ${what} -> ${src} (symlink)"
}

echo "mode: $mode"
if [[ "$mode" == "link" && -z "${XDG_CONFIG_HOME:-}" ]]; then
    echo "note: both files now depend on this directory staying put:"
    echo "      ${SRC_DIR}"
    echo "      If you move it, run ./install.sh --link again, or switch"
    echo "      back with ./install.sh --copy."
fi

# --- the script ---
if [[ "$mode" == "link" ]]; then
    # Executing a symlink uses the *target's* permissions, so the project
    # file has to stay executable or the link silently stops working.
    [[ -x "$SRC" ]] || { chmod +x "$SRC"; echo "made ./urdu-translit executable"; }
    make_link "$DEST" "$SRC" "urdu-translit"
else
    echo "Installing urdu-translit -> $DEST"
    if [[ -L "$DEST" ]]; then
        echo "     (replacing the symlink with a real file)"
        rm -f "$DEST"
    fi
    install -Dm755 "$SRC" "$DEST"
fi

# --- personal corrections ---
# overrides.json is hand-edited and holds the user's own words, so in copy
# mode it is never overwritten on a re-run: doing so would silently delete
# corrections that exist in no other copy. A bad install is recoverable;
# silently losing someone's vocabulary is not.
if [[ -f "$OVERRIDES_SRC" ]]; then
    if [[ "$mode" == "link" ]]; then
        make_link "$OVERRIDES_DEST" "$OVERRIDES_SRC" "overrides.json"
        echo "     edit that file directly; re-running this script is not needed"
    elif [[ -f "$OVERRIDES_DEST" && "$force_overrides" -eq 0 ]]; then
        # Left alone on purpose. But a copy can silently drift from the
        # project file, so say so when they differ - otherwise editing the
        # project copy appears to do nothing, with no explanation.
        if cmp -s "$OVERRIDES_SRC" "$OVERRIDES_DEST"; then
            echo "ok: overrides.json already present and in sync"
        else
            echo "note: overrides.json already present, left untouched, and it"
            echo "      DIFFERS from this project's copy:"
            echo "        live:    ${OVERRIDES_DEST}"
            echo "        project: ${OVERRIDES_SRC}"
            echo "      Your live file is the one in use. To make this project"
            echo "      the source of truth instead, run: ./install.sh --link"
        fi
    else
        mkdir -p "$CONFIG_DIR"
        if [[ -f "$OVERRIDES_DEST" ]]; then
            cp -a "$OVERRIDES_DEST" "${OVERRIDES_DEST}.bak"
            echo "backed up existing overrides.json -> ${OVERRIDES_DEST}.bak"
        fi
        install -Dm644 "$OVERRIDES_SRC" "$OVERRIDES_DEST"
        echo "ok: installed overrides.json -> $OVERRIDES_DEST"
    fi
    # Validate it: a malformed file is ignored wholesale, and the tool only
    # reports that on stderr, which a keybind discards.
    if command -v python3 >/dev/null 2>&1; then
        if python3 -m json.tool "$OVERRIDES_DEST" >/dev/null 2>&1; then
            echo "ok: overrides.json is valid JSON"
        else
            echo "WARN: overrides.json is not valid JSON, so it will be"
            echo "      ignored in full - every word in it stops applying."
            echo "      Fix it with:"
            echo "        python3 -m json.tool ${OVERRIDES_DEST}"
        fi
    fi
else
    echo "note: no overrides.json in the project directory, skipping config"
fi

# --- dependency checks ---
missing=0

if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' \
        && echo "ok: python3 ($(python3 --version 2>&1))" \
        || { echo "warn: python3 found but < 3.10"; missing=1; }
else
    echo "missing: python3 (>= 3.10 required)"
    missing=1
fi

for bin in wl-copy wl-paste; do
    if command -v "$bin" >/dev/null 2>&1; then
        echo "ok: $bin"
    else
        echo "missing: $bin (package: wl-clipboard)"
        missing=1
    fi
done

if command -v wtype >/dev/null 2>&1; then
    echo "ok: wtype"
else
    echo "missing: wtype (needed for --clip in-place paste)"
    missing=1
fi

if ! command -v notify-send >/dev/null 2>&1; then
    echo "warn: notify-send not found (failure popups disabled)"
fi

if [[ ":$PATH:" != *":${HOME}/.local/bin:"* ]]; then
    echo "warn: ~/.local/bin is not on PATH. Add to ~/.config/uwsm/env (UWSM):"
    echo '  export PATH="$HOME/.local/bin:$PATH"'
fi

if [[ "$missing" -eq 1 ]]; then
    echo ""
    echo "Install missing packages (CachyOS/Arch):"
    echo "  sudo pacman -S wl-clipboard wtype"
fi

# --- verify ---
echo ""
if [[ -x "$DEST" && ! -L "$DEST" ]]; then
    echo "ok: $DEST (real file)"
elif [[ -L "$DEST" && -e "$DEST" && -x "$DEST" ]]; then
    echo "ok: $DEST (symlink, resolves and is executable)"
else
    echo "WARN: $DEST is not runnable - the keybindings will fail."
    [[ -L "$DEST" ]] && echo "      the symlink is broken; its target is:"
    [[ -L "$DEST" ]] && echo "        $(readlink "$DEST")"
    missing=1
fi
command -v urdu-translit >/dev/null 2>&1 \
    && echo "ok: $(command -v urdu-translit) is on PATH" \
    || echo "warn: urdu-translit not on PATH yet (open a new shell or use $DEST)"

# Remember the choice, so the next plain ./install.sh keeps the same layout
# instead of quietly reverting symlinks to copies.
mkdir -p "$CONFIG_DIR"
printf '%s\n' "$mode" > "$MODE_FILE"

echo ""
echo "Run a quick check (needs network once, then cached):"
echo "  urdu-translit --selftest"
echo "  urdu-translit \"aap kise hen\""
echo ""
echo "Edit your personal corrections in:"
echo "  ${OVERRIDES_DEST}"
if [[ "$mode" == "link" ]]; then
    echo ""
    echo "That is a symlink. Edit ${OVERRIDES_SRC} instead if you prefer"
    echo "working in the project directory."
fi
