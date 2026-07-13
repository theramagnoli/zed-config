#!/bin/sh
# Synchronize Zed's portable configuration from this Git checkout.
#
# Shared keymap entries use {{primary}}. It renders to cmd on macOS and ctrl
# on Windows/WSL/Linux. Zed calls the Option key "alt", so alt needs no change.

set -eu

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SETTINGS_FILE="$REPO_DIR/settings.json"
KEYMAP_TEMPLATE="$REPO_DIR/keymap.json.tmpl"
EXTRAS_DIR="$REPO_DIR/config"
SETTINGS_TOOL="$REPO_DIR/scripts/sync-settings.py"
CONFIG_DIR_OVERRIDE=${ZED_CONFIG_DIR:-}

die() {
    printf '%s\n' "error: $*" >&2
    exit 1
}

detect_target() {
    if [ "$(uname -s)" = "Darwin" ]; then
        PLATFORM=macos
        PRIMARY=cmd
        ZED_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zed"
        ZED_DEBUG_FILE="$HOME/Library/Application Support/Zed/debug.json"
        SETTINGS_OVERLAY="$EXTRAS_DIR/platform/macos.json"
    elif [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
        PLATFORM=wsl
        PRIMARY=ctrl
        command -v powershell.exe >/dev/null 2>&1 || die "powershell.exe is required to locate Windows %APPDATA% from WSL"
        command -v wslpath >/dev/null 2>&1 || die "wslpath is required to translate the Windows config path"
        win_appdata=$(powershell.exe -NoProfile -Command '[Environment]::GetFolderPath("ApplicationData")' | tr -d '\r')
        [ -n "$win_appdata" ] || die "could not determine Windows %APPDATA%"
        ZED_CONFIG_DIR="$(wslpath -u "$win_appdata")/Zed"
        ZED_DEBUG_FILE="$ZED_CONFIG_DIR/debug.json"
        SETTINGS_OVERLAY="$EXTRAS_DIR/platform/windows.json"
    elif [ -n "${APPDATA:-}" ] && uname -s | grep -qE '^(MINGW|MSYS|CYGWIN)'; then
        PLATFORM=windows
        PRIMARY=ctrl
        ZED_CONFIG_DIR="$APPDATA/Zed"
        ZED_DEBUG_FILE="$ZED_CONFIG_DIR/debug.json"
        SETTINGS_OVERLAY="$EXTRAS_DIR/platform/windows.json"
    else
        PLATFORM=linux
        PRIMARY=ctrl
        ZED_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zed"
        ZED_DEBUG_FILE="$ZED_CONFIG_DIR/debug.json"
        SETTINGS_OVERLAY="$EXTRAS_DIR/platform/linux.json"
    fi

    if [ -n "$CONFIG_DIR_OVERRIDE" ]; then
        ZED_CONFIG_DIR=$CONFIG_DIR_OVERRIDE
        ZED_DEBUG_FILE="$ZED_CONFIG_DIR/debug.json"
    fi
}

render_keymap() {
    sed "s/{{primary}}/$PRIMARY/g" "$KEYMAP_TEMPLATE"
}

require_settings_tool() {
    [ -f "$SETTINGS_TOOL" ] || die "missing $SETTINGS_TOOL"
    command -v python3 >/dev/null 2>&1 || die "python3 is required to merge platform settings"
}

render_settings() {
    destination_file=$1
    if [ -f "$SETTINGS_OVERLAY" ]; then
        require_settings_tool
        python3 "$SETTINGS_TOOL" render "$SETTINGS_FILE" "$SETTINGS_OVERLAY" "$destination_file"
    else
        cp "$SETTINGS_FILE" "$destination_file"
    fi
}

capture_settings() {
    source_file=$1
    if [ -f "$SETTINGS_OVERLAY" ]; then
        require_settings_tool
        python3 "$SETTINGS_TOOL" capture "$source_file" "$SETTINGS_FILE" "$SETTINGS_OVERLAY"
    else
        cp "$source_file" "$SETTINGS_FILE"
    fi
}

backup_if_present() {
    file=$1
    [ -e "$file" ] || return 0
    if [ -z "${BACKUP_DIR:-}" ]; then
        BACKUP_DIR="$ZED_CONFIG_DIR/backups/$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$BACKUP_DIR"
    fi
    cp -R "$file" "$BACKUP_DIR/$(basename "$file")"
    printf 'Backed up %s to %s\n' "$file" "$BACKUP_DIR"
}

mirror_optional_file() {
    source_file=$1
    destination_file=$2
    if [ -f "$source_file" ]; then
        mkdir -p "$(dirname "$destination_file")"
        cp "$source_file" "$destination_file"
    else
        rm -f "$destination_file"
    fi
}

mirror_optional_dir() {
    source_dir=$1
    destination_dir=$2
    rm -rf "$destination_dir"
    if [ -d "$source_dir" ]; then
        mkdir -p "$(dirname "$destination_dir")"
        cp -R "$source_dir" "$destination_dir"
    fi
}

backup_safe_files() {
    backup_if_present "$ZED_CONFIG_DIR/settings.json"
    backup_if_present "$ZED_CONFIG_DIR/keymap.json"
    backup_if_present "$ZED_CONFIG_DIR/AGENTS.md"
    backup_if_present "$ZED_CONFIG_DIR/tasks.json"
    backup_if_present "$ZED_DEBUG_FILE"
    backup_if_present "$ZED_CONFIG_DIR/themes"
    backup_if_present "$ZED_CONFIG_DIR/snippets"
}

pull() {
    [ -f "$SETTINGS_FILE" ] || die "missing $SETTINGS_FILE"
    [ -f "$KEYMAP_TEMPLATE" ] || die "missing $KEYMAP_TEMPLATE"
    mkdir -p "$ZED_CONFIG_DIR"
    backup_safe_files
    render_settings "$ZED_CONFIG_DIR/settings.json"
    render_keymap > "$ZED_CONFIG_DIR/keymap.json"
    mirror_optional_file "$EXTRAS_DIR/AGENTS.md" "$ZED_CONFIG_DIR/AGENTS.md"
    mirror_optional_file "$EXTRAS_DIR/tasks.json" "$ZED_CONFIG_DIR/tasks.json"
    mirror_optional_file "$EXTRAS_DIR/debug.json" "$ZED_DEBUG_FILE"
    mirror_optional_dir "$EXTRAS_DIR/themes" "$ZED_CONFIG_DIR/themes"
    mirror_optional_dir "$EXTRAS_DIR/snippets" "$ZED_CONFIG_DIR/snippets"
    printf 'Applied %s configuration to %s\n' "$PLATFORM" "$ZED_CONFIG_DIR"
}

push() {
    [ -f "$ZED_CONFIG_DIR/settings.json" ] || die "Zed settings not found: $ZED_CONFIG_DIR/settings.json"
    [ -f "$ZED_CONFIG_DIR/keymap.json" ] || die "Zed keymap not found: $ZED_CONFIG_DIR/keymap.json"
    capture_settings "$ZED_CONFIG_DIR/settings.json"

    # Promote this machine's primary modifier back into the portable token.
    # The boundary rule avoids changing action names such as "ctrl::Action".
    sed -E "s/(^|[^[:alnum:]_])$PRIMARY([^[:alnum:]_]|$)/\\1{{primary}}\\2/g" \
        "$ZED_CONFIG_DIR/keymap.json" > "$KEYMAP_TEMPLATE"
    # keymap.json used to be a platform-specific source file. The template
    # supersedes it, so remove it once it is tracked as deleted in Git.
    rm -f "$REPO_DIR/keymap.json"
    mkdir -p "$EXTRAS_DIR"
    mirror_optional_file "$ZED_CONFIG_DIR/AGENTS.md" "$EXTRAS_DIR/AGENTS.md"
    mirror_optional_file "$ZED_CONFIG_DIR/tasks.json" "$EXTRAS_DIR/tasks.json"
    mirror_optional_file "$ZED_DEBUG_FILE" "$EXTRAS_DIR/debug.json"
    mirror_optional_dir "$ZED_CONFIG_DIR/themes" "$EXTRAS_DIR/themes"
    mirror_optional_dir "$ZED_CONFIG_DIR/snippets" "$EXTRAS_DIR/snippets"
    printf 'Captured %s configuration into %s\n' "$PLATFORM" "$REPO_DIR"
    printf 'Review the diff, then commit and push it with Git.\n'
}

status() {
    printf 'Platform: %s\nZed config: %s\nPrimary modifier: %s\n' "$PLATFORM" "$ZED_CONFIG_DIR" "$PRIMARY"
    settings_temp=$(mktemp)
    keymap_temp=$(mktemp)
    trap 'rm -f "$settings_temp" "$keymap_temp"' EXIT HUP INT TERM
    render_settings "$settings_temp"
    [ -f "$ZED_CONFIG_DIR/settings.json" ] && diff -q "$settings_temp" "$ZED_CONFIG_DIR/settings.json" >/dev/null \
        && printf 'settings: in sync\n' || printf 'settings: differ or missing\n'
    render_keymap > "$keymap_temp"
    [ -f "$ZED_CONFIG_DIR/keymap.json" ] && diff -q "$keymap_temp" "$ZED_CONFIG_DIR/keymap.json" >/dev/null \
        && printf 'keymap: in sync\n' || printf 'keymap: differ or missing\n'
}

usage() {
    cat <<'EOF'
Usage: ./sync-zed.sh <pull|push|status>

  pull    Apply the safe configuration bundle to Zed (with local backups).
  push    Capture this machine's safe configuration bundle into the repo.
  status  Show the detected target and whether it matches the repository.

The bundle includes settings, keymap, AGENTS.md, global tasks/debug definitions,
local themes, and snippets. It intentionally excludes authentication, databases,
extensions, prompt-library data, logs, caches, and backups.

Run `push` after deliberately changing Zed configuration on either computer;
review the resulting Git diff before committing. Run `pull` on the other computer.
EOF
}

detect_target
case "${1:-}" in
    pull) pull ;;
    push) push ;;
    status) status ;;
    -h|--help|help|'') usage ;;
    *) die "unknown command: $1 (try --help)" ;;
esac
