#!/usr/bin/env python3
"""Render and capture Zed JSONC settings with a platform overlay."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Any

# Keep the settings users tune most often together at the beginning. Every other
# setting, including all nested objects, is written in alphabetical order.
SETTINGS_PRIORITY = (
    "theme",
    "icon_theme",
    "ui_font_family",
    "ui_font_size",
    "ui_font_weight",
    "buffer_font_family",
    "buffer_font_features",
    "buffer_font_size",
    "buffer_font_weight",
    "buffer_line_height",
    "agent_buffer_font_size",
    "agent_ui_font_size",
    "text_rendering_mode",
)


def strip_jsonc(text: str) -> str:
    """Remove JSONC comments and trailing commas without touching strings."""
    without_comments: list[str] = []
    index = 0
    in_string = False
    escaped = False

    while index < len(text):
        char = text[index]

        if in_string:
            without_comments.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue

        if char == '"':
            in_string = True
            without_comments.append(char)
            index += 1
            continue

        if char == "/" and index + 1 < len(text):
            next_char = text[index + 1]
            if next_char == "/":
                index += 2
                while index < len(text) and text[index] not in "\r\n":
                    index += 1
                continue
            if next_char == "*":
                index += 2
                while index + 1 < len(text) and text[index : index + 2] != "*/":
                    if text[index] in "\r\n":
                        without_comments.append(text[index])
                    index += 1
                index += 2
                continue

        without_comments.append(char)
        index += 1

    cleaned = "".join(without_comments)
    without_trailing_commas: list[str] = []
    index = 0
    in_string = False
    escaped = False

    while index < len(cleaned):
        char = cleaned[index]

        if in_string:
            without_trailing_commas.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue

        if char == '"':
            in_string = True
        elif char == ",":
            lookahead = index + 1
            while lookahead < len(cleaned) and cleaned[lookahead].isspace():
                lookahead += 1
            if lookahead < len(cleaned) and cleaned[lookahead] in "}]":
                index += 1
                continue

        without_trailing_commas.append(char)
        index += 1

    return "".join(without_trailing_commas)


def load_jsonc(path: Path) -> Any:
    return json.loads(strip_jsonc(path.read_text(encoding="utf-8")))


def load_jsonc_object(path: Path) -> dict[str, Any]:
    parsed = load_jsonc(path)
    if not isinstance(parsed, dict):
        raise ValueError(f"expected a JSON object in {path}")
    return parsed


def sort_json(value: Any, priority_keys: tuple[str, ...] = ()) -> Any:
    """Recursively sort JSON objects, optionally pinning root keys first."""
    if isinstance(value, dict):
        ordered_keys = [key for key in priority_keys if key in value]
        ordered_keys.extend(sorted(key for key in value if key not in priority_keys))
        return {key: sort_json(value[key]) for key in ordered_keys}
    if isinstance(value, list):
        return [sort_json(item) for item in value]
    return value


def write_json(
    path: Path,
    value: Any,
    priority_keys: tuple[str, ...] = (),
    *,
    sort_keys: bool = False,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary_file:
            json.dump(
                sort_json(value, priority_keys) if sort_keys else value,
                temporary_file,
                ensure_ascii=False,
                indent=4,
            )
            temporary_file.write("\n")
        os.replace(temporary_name, path)
    except Exception:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def deep_merge(base: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
    result = dict(base)
    for key, overlay_value in overlay.items():
        base_value = result.get(key)
        if isinstance(base_value, dict) and isinstance(overlay_value, dict):
            result[key] = deep_merge(base_value, overlay_value)
        else:
            result[key] = overlay_value
    return result


def normalize(input_path: Path, output_path: Path) -> None:
    priority_keys = SETTINGS_PRIORITY if output_path.name == "settings.json" else ()
    write_json(
        output_path,
        load_jsonc(input_path),
        priority_keys,
        sort_keys=bool(priority_keys),
    )


def render(base_path: Path, overlay_path: Path, output_path: Path) -> None:
    write_json(
        output_path,
        deep_merge(load_jsonc_object(base_path), load_jsonc_object(overlay_path)),
        SETTINGS_PRIORITY,
        sort_keys=True,
    )


def capture(local_path: Path, base_path: Path, overlay_path: Path) -> None:
    local = load_jsonc_object(local_path)
    existing_overlay = load_jsonc_object(overlay_path)
    captured_overlay: dict[str, Any] = {}

    # Top-level keys present in the overlay are declared platform-specific.
    # Keep their previous value if Zed omitted one, or capture the current
    # platform value when it is present (including an intentionally empty list).
    for key, previous_value in existing_overlay.items():
        captured_overlay[key] = local.pop(key, previous_value)

    write_json(base_path, local, SETTINGS_PRIORITY, sort_keys=True)
    write_json(overlay_path, captured_overlay, sort_keys=True)


def staged_file_statuses(repository: Path) -> list[tuple[str, str]]:
    """Return staged paths and their Git status, including rename destinations."""
    result = subprocess.run(
        ["git", "-C", str(repository), "diff", "--cached", "--name-status", "-z"],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    fields = iter(result.stdout.split("\0"))
    statuses: list[tuple[str, str]] = []
    for status in fields:
        if not status:
            continue
        path = next(fields)
        if status[0] in {"R", "C"}:
            path = next(fields)
        statuses.append((status[0], path))
    return statuses


def staged_json(repository: Path, revision: str, path: str) -> dict[str, Any]:
    result = subprocess.run(
        [
            "git",
            "-C",
            str(repository),
            "show",
            f":{path}" if revision == ":" else f"{revision}:{path}",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    if result.returncode:
        return {}
    parsed = load_jsonc_text(result.stdout)
    return parsed if isinstance(parsed, dict) else {}


def load_jsonc_text(text: str) -> Any:
    return json.loads(strip_jsonc(text))


def settings_change_summary(repository: Path) -> str | None:
    before = staged_json(repository, "HEAD", "settings.json")
    after = staged_json(repository, ":", "settings.json")
    changes = [
        key
        for key in sorted(set(before) | set(after))
        if before.get(key) != after.get(key)
    ]
    if not changes:
        return None
    return "settings.json: " + ", ".join(changes)


def staged_summary(repository: Path) -> str:
    """Create a concise Spanish commit body for the staged configuration bundle."""
    lines: list[str] = []
    for status, path in staged_file_statuses(repository):
        if path == "settings.json":
            summary = settings_change_summary(repository)
            lines.append(f"- {summary or 'settings.json actualizado'}")
            continue
        action = {
            "A": "agregado",
            "D": "eliminado",
            "M": "actualizado",
            "R": "renombrado",
        }.get(status, "actualizado")
        lines.append(f"- {path}: {action}")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    normalize_parser = subparsers.add_parser("normalize")
    normalize_parser.add_argument("input", type=Path)
    normalize_parser.add_argument("output", type=Path)

    render_parser = subparsers.add_parser("render")
    render_parser.add_argument("base", type=Path)
    render_parser.add_argument("overlay", type=Path)
    render_parser.add_argument("output", type=Path)

    capture_parser = subparsers.add_parser("capture")
    capture_parser.add_argument("local", type=Path)
    capture_parser.add_argument("base", type=Path)
    capture_parser.add_argument("overlay", type=Path)

    summary_parser = subparsers.add_parser("staged-summary")
    summary_parser.add_argument("repository", type=Path)

    arguments = parser.parse_args()
    if arguments.command == "normalize":
        normalize(arguments.input, arguments.output)
    elif arguments.command == "render":
        render(arguments.base, arguments.overlay, arguments.output)
    elif arguments.command == "capture":
        capture(arguments.local, arguments.base, arguments.overlay)
    else:
        print(staged_summary(arguments.repository))


if __name__ == "__main__":
    main()
