# Zed configuration

This repository keeps a portable, non-secret Zed setup for macOS and a Windows machine used through WSL.

## Install the command

Install the CLI and completions for Bash, Zsh, and Fish:

```sh
./sync-zed.sh install
```

This creates `~/.local/bin/zed-config` as a symlink to this checkout. Ensure `~/.local/bin` is in `PATH`, then restart your shell and use the command from anywhere:

```sh
zed-config status
zed-config push
```

The installer writes completion definitions to the standard user directories for all three shells. Zsh users whose configuration does not already include `~/.zfunc` should add this before their `compinit` call:

```zsh
fpath=(~/.zfunc $fpath)
autoload -Uz compinit && compinit
```

Set `ZED_CONFIG_BIN_DIR` to choose another executable directory. Completion definitions can also be printed for manual setup with `zed-config completion bash`, `zed-config completion zsh`, or `zed-config completion fish`.

Because the installed command points to this checkout, keep the repository in place. Re-running `install` safely refreshes the symlink and completion files.

## Sync it

For the usual two-machine workflow, keep both checkouts on `main`. After changing Zed settings on one machine:
After changing Zed settings on one machine:

```sh
zed-config push
```

This captures the safe configuration bundle, creates a timestamped commit such as `Copia 14/04/2026 7:30 AM`, and pushes `main` to `origin`.

On the other computer:

```sh
zed-config pull
```

This requires a clean `main` checkout, fast-forwards from `origin/main`, backs up the current Zed files, and applies the downloaded configuration. `zed-config status` reports whether Zed matches the checkout.

`push-remote` and `pull-remote` remain available as aliases for compatibility. Script and documentation commits follow `Se <enunciado>`; automatic configuration snapshots follow `Copia DD/MM/YYYY h:mm AM/PM`. Development branch names use English, for example `agent/add-remote-sync-commands`.

## Cross-platform keymap

`keymap.json.tmpl` is the source of truth. It uses `{{primary}}` for the platform's primary shortcut modifier:

| Runtime                  | Zed directory           | `{{primary}}` |
| ------------------------ | ----------------------- | ------------- |
| macOS                    | `~/.config/zed`         | `cmd`         |
| WSL (Windows-hosted Zed) | Windows `%APPDATA%/Zed` | `ctrl`        |
| Linux                    | `~/.config/zed`         | `ctrl`        |

Zed uses `alt` for the macOS Option key as well as the Windows Alt key, so `alt` bindings remain unchanged. The script recognizes WSL and uses `powershell.exe` plus `wslpath` to write to the Windows Zed configuration—not a separate WSL-only config directory.

If you run a Linux build of Zed **inside** WSL rather than Windows-hosted Zed, override the destination explicitly:

```sh
ZED_CONFIG_DIR="$HOME/.config/zed" ./sync-zed.sh pull
```

`push` promotes the current platform's `cmd`/`ctrl` bindings back into `{{primary}}`. For a command that is deliberately different by platform, keep the template and add an explicit platform-specific binding after running `push`.

## Platform-specific settings

`settings.json` contains the shared configuration. Files under `config/platform/` are overlays whose top-level keys remain specific to that platform.

The Windows overlay owns `wsl_connections`. During `pull`, the script merges those connections into the shared settings before writing `%APPDATA%/Zed/settings.json`. During a Windows/WSL `push`, it extracts the same key back into the overlay, so a later Mac update cannot erase the saved WSL projects.

Platform merging requires `python3`; the helper supports Zed's JSON-with-comments and trailing commas.

## What is synced

`push` and `pull` mirror this safe bundle:

- `settings.json` and the platform-rendered keymap
- `AGENTS.md` (global agent instructions)
- global `tasks.json` and `debug.json`, when present
- local `themes/` and `snippets/` directories

`pull` creates timestamped backups of those destination files first.

The script intentionally excludes Zed databases, prompt-library data, extensions and extension state, logs, caches, sessions, lockfiles, local backups, and authentication data. Provider keys are stored in the OS keychain rather than `settings.json`, but external-agent credentials can have their own storage and are not copied.
