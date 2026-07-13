# Zed configuration

This repository keeps a portable, non-secret Zed setup for macOS and a Windows machine used through WSL.

## Sync it

From a checkout of this repository:

```sh
chmod +x sync-zed.sh
./sync-zed.sh push      # capture the current machine's Zed configuration
git diff                # inspect the changes
git add -A && git commit -m "Update Zed configuration"
git push
```

On the other computer, update the checkout and apply it:

```sh
git pull --ff-only
./sync-zed.sh pull
```

`./sync-zed.sh status` reports the target directory and whether it matches the checkout.

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
