#!/bin/sh
# Synchronize Zed's portable configuration from this Git checkout.
#
# Shared keymap entries use {{primary}}. It renders to cmd on macOS and ctrl
# on Windows/WSL/Linux. Zed calls the Option key "alt", so alt needs no change.

set -eu

SCRIPT_PATH=$0
while [ -L "$SCRIPT_PATH" ]; do
    script_dir=$(CDPATH= cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)
    link_target=$(readlink "$SCRIPT_PATH")
    case "$link_target" in
        /*) SCRIPT_PATH=$link_target ;;
        *) SCRIPT_PATH=$script_dir/$link_target ;;
    esac
done
REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)
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

require_main_checkout() {
    git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
        || die "$REPO_DIR is not a Git repository"
    git -C "$REPO_DIR" remote get-url origin >/dev/null 2>&1 \
        || die "Git remote 'origin' is not configured"
    branch=$(git -C "$REPO_DIR" branch --show-current)
    [ "$branch" = "main" ] || die "remote sync requires branch 'main' (current: ${branch:-detached HEAD})"
}

require_clean_checkout() {
    changes=$(git -C "$REPO_DIR" status --porcelain)
    [ -z "$changes" ] || die "the repository has uncommitted changes; commit or discard them before pull"
}

require_only_config_changes() {
    unrelated=$(git -C "$REPO_DIR" status --porcelain -- . \
        ':(exclude)settings.json' \
        ':(exclude)keymap.json.tmpl' \
        ':(exclude)config/**')
    [ -z "$unrelated" ] || {
        printf '%s\n' "$unrelated" >&2
        die "unrelated repository changes found; commit them separately before push"
    }
}

require_current_remote_main() {
    git -C "$REPO_DIR" fetch origin main
    local_head=$(git -C "$REPO_DIR" rev-parse HEAD)
    remote_head=$(git -C "$REPO_DIR" rev-parse origin/main)
    [ "$local_head" = "$remote_head" ] \
        || die "local main does not match origin/main; run pull before changing Zed"
}

snapshot_commit_message() {
    timestamp=$(date '+%d/%m/%Y %I:%M %p' | sed 's/ 0/ /')
    printf 'Copia %s\n' "$timestamp"
}

push_remote() {
    [ "$#" -eq 0 ] || die "push does not accept a message; it generates 'Copia DD/MM/YYYY h:mm AM/PM'"
    require_main_checkout
    require_only_config_changes
    require_current_remote_main
    push

    git -C "$REPO_DIR" add -A -- settings.json keymap.json.tmpl config
    if git -C "$REPO_DIR" diff --cached --quiet -- settings.json keymap.json.tmpl config; then
        printf 'No configuration changes to commit.\n'
    else
        message=$(snapshot_commit_message)
        git -C "$REPO_DIR" commit -m "$message"
    fi

    git -C "$REPO_DIR" push origin main
}

pull_remote() {
    [ "$#" -eq 0 ] || die "pull does not accept arguments"
    require_main_checkout
    require_clean_checkout
    git -C "$REPO_DIR" pull --ff-only origin main
    pull
}

completion() {
    [ "$#" -eq 1 ] || die "usage: zed-config completion <bash|zsh|fish>"
    case "$1" in
        bash)
            cat <<'EOF'
_zed_config() {
    local commands="pull push status pull-remote push-remote install completion help"
    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=($(compgen -W "$commands" -- "${COMP_WORDS[COMP_CWORD]}"))
    elif [ "$COMP_CWORD" -eq 2 ] && [ "${COMP_WORDS[1]}" = completion ]; then
        COMPREPLY=($(compgen -W "bash zsh fish" -- "${COMP_WORDS[COMP_CWORD]}"))
    else
        COMPREPLY=()
    fi
}
complete -F _zed_config zed-config
EOF
            ;;
        zsh)
            cat <<'EOF'
#compdef zed-config
_zed-config() {
    local -a commands
    commands=(
        'pull:Update from origin/main and apply configuration'
        'push:Capture, commit, and push configuration'
        'status:Show sync status'
        'pull-remote:Alias for pull'
        'push-remote:Alias for push'
        'install:Install the command and shell completions'
        'completion:Print a shell completion script'
        'help:Show help'
    )
    if (( CURRENT == 2 )); then
        _describe 'command' commands
    elif (( CURRENT == 3 )) && [[ $words[2] == completion ]]; then
        _values 'shell' bash zsh fish
    fi
}
compdef _zed-config zed-config
EOF
            ;;
        fish)
            cat <<'EOF'
complete -c zed-config -f
complete -c zed-config -n '__fish_use_subcommand' -a pull -d 'Update from origin/main and apply configuration'
complete -c zed-config -n '__fish_use_subcommand' -a push -d 'Capture, commit, and push configuration'
complete -c zed-config -n '__fish_use_subcommand' -a status -d 'Show sync status'
complete -c zed-config -n '__fish_use_subcommand' -a pull-remote -d 'Alias for pull'
complete -c zed-config -n '__fish_use_subcommand' -a push-remote -d 'Alias for push'
complete -c zed-config -n '__fish_use_subcommand' -a install -d 'Install the command and shell completions'
complete -c zed-config -n '__fish_use_subcommand' -a completion -d 'Print a shell completion script'
complete -c zed-config -n '__fish_seen_subcommand_from completion' -a 'bash zsh fish'
complete -c zed-config -n '__fish_use_subcommand' -a help -d 'Show help'
EOF
            ;;
        *) die "unsupported shell: $1 (expected bash, zsh, or fish)" ;;
    esac
}

install_cli() {
    [ "$#" -eq 0 ] || die "install does not accept arguments"
    bin_dir=${ZED_CONFIG_BIN_DIR:-$HOME/.local/bin}
    mkdir -p "$bin_dir"
    ln -sf "$REPO_DIR/sync-zed.sh" "$bin_dir/zed-config"

    bash_dir=${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions
    zsh_dir=${ZDOTDIR:-$HOME}/.zfunc
    fish_dir=${XDG_CONFIG_HOME:-$HOME/.config}/fish/completions
    mkdir -p "$bash_dir" "$zsh_dir" "$fish_dir"
    completion bash > "$bash_dir/zed-config"
    completion zsh > "$zsh_dir/_zed-config"
    completion fish > "$fish_dir/zed-config.fish"

    printf 'Installed zed-config to %s\n' "$bin_dir/zed-config"
    case ":$PATH:" in
        *":$bin_dir:"*) ;;
        *) printf 'Add %s to PATH to run zed-config from anywhere.\n' "$bin_dir" ;;
    esac
    printf 'Shell completions installed. Restart your shell to activate them.\n'
    printf 'Zsh users: if completion is unavailable, add fpath=(%s $fpath) before compinit.\n' "$zsh_dir"
}

usage() {
    cat <<'EOF'
Usage: zed-config <command>

  pull         Fast-forward origin/main, then apply its configuration to Zed.
  push         Capture, commit as "Copia <timestamp>", and push origin/main.
  pull-remote  Alias for pull (kept for compatibility).
  push-remote  Alias for push (kept for compatibility).
  status       Show the detected target and whether it matches the repository.
  install      Install zed-config and Bash, Zsh, and Fish completions.
  completion   Print completion code: completion <bash|zsh|fish>.

The bundle includes settings, keymap, AGENTS.md, global tasks/debug definitions,
local themes, and snippets. It intentionally excludes authentication, databases,
extensions, prompt-library data, logs, caches, and backups.

Run `push` after deliberately changing Zed configuration on either computer;
review the resulting Git diff before committing. Run `pull` on the other computer.

Remote commands require a main-branch checkout. Development branches use
English names. Code changes use Spanish "Se <enunciado>" commits;
push uses "Copia DD/MM/YYYY h:mm AM/PM".
EOF
}

case "${1:-}" in
    pull|pull-remote) shift; detect_target; pull_remote "$@" ;;
    push|push-remote) shift; detect_target; push_remote "$@" ;;
    status) detect_target; status ;;
    install) shift; install_cli "$@" ;;
    completion) shift; completion "$@" ;;
    -h|--help|help|'') usage ;;
    *) die "unknown command: $1 (try --help)" ;;
esac
