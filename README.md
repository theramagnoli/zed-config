# Zed configuration

This repository keeps a portable, non-secret Zed setup for three runtimes:

| Runtime | Notes |
| ------- | ----- |
| macOS | Native Zed |
| Windows via WSL | Sync from WSL into Windows-hosted Zed (`%APPDATA%/Zed`) |
| Native Linux | e.g. Pop!_OS — native Zed under `~/.config/zed` |

## Prerequisites

- Git, `python3`, and a Zed install on the target machine
- **Monaspace Radon** installed as a system font (UI and buffer font)
- On WSL → Windows Zed: `powershell.exe` and `wslpath` available in the distro

Theme and icon extensions referenced by the shared settings are declared in `auto_install_extensions`, so Zed installs them on first launch:

- `macos-classic` (macOS Classic Light/Dark themes)
- `colored-zed-icons-theme`
- `html`

## Install the command

Clone this repository to a permanent location (the installed command is a symlink into the checkout), then:

```sh
./sync-zed.sh install
zed-config pull
```

This creates `~/.local/bin/zed-config` as a symlink to this checkout. Ensure `~/.local/bin` is in `PATH`, then restart your shell and use the command from anywhere:

```sh
zed-config status
zed-config push
```

The installer writes completion definitions to the standard user directories for Bash, Zsh, and Fish. Zsh users whose configuration does not already include `~/.zfunc` should add this before their `compinit` call:

```zsh
fpath=(~/.zfunc $fpath)
autoload -Uz compinit && compinit
```

Set `ZED_CONFIG_BIN_DIR` to choose another executable directory. Completion definitions can also be printed for manual setup with `zed-config completion bash`, `zed-config completion zsh`, or `zed-config completion fish`.

Because the installed command points to this checkout, keep the repository in place. Re-running `install` safely refreshes the symlink and completion files.

## Sync it

Keep every checkout on `main`. After changing Zed settings on one machine:

```sh
zed-config push
```

This captures the safe configuration bundle, creates a timestamped commit such as `Copia 14/04/2026 7:30 AM`, adds an automatic description of the changed settings and synced files, and pushes `main` to `origin`.

On another computer:

```sh
zed-config pull
```

This requires a clean `main` checkout, fast-forwards from `origin/main`, backs up the current Zed files, and applies the downloaded configuration. `zed-config status` reports whether Zed matches the checkout.

`push-remote` and `pull-remote` remain available as aliases for compatibility. Script and documentation commits follow `Se <enunciado>`; automatic configuration snapshots use `Copia DD/MM/YYYY h:mm AM/PM` as their subject and include a generated configuration-change summary in the commit body. Development branch names use English, for example `agent/add-remote-sync-commands`.

## Cross-platform keymap

`keymap.json.tmpl` is the source of truth. It uses `{{primary}}` for the platform's primary shortcut modifier:

| Runtime                  | Zed directory           | `{{primary}}` |
| ------------------------ | ----------------------- | ------------- |
| macOS                    | `~/.config/zed`         | `cmd`         |
| WSL (Windows-hosted Zed) | Windows `%APPDATA%/Zed` | `ctrl`        |
| Linux (native Zed)       | `~/.config/zed`         | `ctrl`        |

Zed uses `alt` for the macOS Option key as well as the Windows/Linux Alt key, so `alt` bindings remain unchanged. The script recognizes WSL and uses `powershell.exe` plus `wslpath` to write to the Windows Zed configuration—not a separate WSL-only config directory.

If you run a Linux build of Zed **inside** WSL rather than Windows-hosted Zed, override the destination explicitly:

```sh
ZED_CONFIG_DIR="$HOME/.config/zed" ./sync-zed.sh pull
```

`push` promotes the current platform's `cmd`/`ctrl` bindings back into `{{primary}}`. For a command that is deliberately different by platform, keep the template and add an explicit platform-specific binding after running `push`.

## Platform-specific settings

`settings.json` contains the shared configuration. Its nested objects are written alphabetically whenever the configuration is captured; the top-level appearance and font settings stay together at the beginning, followed by the remaining settings alphabetically. Files under `config/platform/` are overlays whose top-level keys remain specific to that platform:

| Overlay | Used on | Typical keys |
| ------- | ------- | ------------ |
| `config/platform/windows.json` | Windows / WSL | `wsl_connections` |
| `config/platform/macos.json` | macOS | optional Mac-only keys |
| `config/platform/linux.json` | native Linux | optional Linux-only keys |

The Windows overlay owns `wsl_connections`. During `pull`, the script merges those connections into the shared settings before writing `%APPDATA%/Zed/settings.json`. During a Windows/WSL `push`, it extracts the same key back into the overlay, so a later Mac or Linux update cannot erase the saved WSL projects.

Missing overlay files are fine: the shared `settings.json` is applied as-is.

JSON processing requires `python3`. The helper accepts Zed's JSON-with-comments and trailing commas as input, then writes strict JSON without comments or trailing commas for settings, keymaps, tasks, debug definitions, themes, and snippets.

## What is synced

`push` and `pull` mirror this safe bundle:

- `settings.json` and the platform-rendered keymap
- `AGENTS.md` (global agent instructions)
- global `tasks.json` and `debug.json`, when present
- local `themes/` and `snippets/` directories

`pull` creates timestamped backups of those destination files first.

The script intentionally excludes Zed databases, prompt-library data, extensions and extension state, logs, caches, sessions, lockfiles, local backups, and authentication data. Provider keys are stored in the OS keychain rather than `settings.json`, but external-agent credentials can have their own storage and are not copied. Extensions themselves are reinstalled via `auto_install_extensions` rather than copied between machines.
