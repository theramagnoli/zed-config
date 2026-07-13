#!/usr/bin/env python3
"""Render and capture Zed JSONC settings with a platform overlay."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path
from typing import Any


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


def load_jsonc(path: Path) -> dict[str, Any]:
    parsed = json.loads(strip_jsonc(path.read_text(encoding="utf-8")))
    if not isinstance(parsed, dict):
        raise ValueError(f"expected a JSON object in {path}")
    return parsed


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary_file:
            json.dump(value, temporary_file, ensure_ascii=False, indent=4)
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


def render(base_path: Path, overlay_path: Path, output_path: Path) -> None:
    write_json(output_path, deep_merge(load_jsonc(base_path), load_jsonc(overlay_path)))


def capture(local_path: Path, base_path: Path, overlay_path: Path) -> None:
    local = load_jsonc(local_path)
    existing_overlay = load_jsonc(overlay_path)
    captured_overlay: dict[str, Any] = {}

    # Top-level keys present in the overlay are declared platform-specific.
    # Keep their previous value if Zed omitted one, or capture the current
    # platform value when it is present (including an intentionally empty list).
    for key, previous_value in existing_overlay.items():
        captured_overlay[key] = local.pop(key, previous_value)

    write_json(base_path, local)
    write_json(overlay_path, captured_overlay)


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    render_parser = subparsers.add_parser("render")
    render_parser.add_argument("base", type=Path)
    render_parser.add_argument("overlay", type=Path)
    render_parser.add_argument("output", type=Path)

    capture_parser = subparsers.add_parser("capture")
    capture_parser.add_argument("local", type=Path)
    capture_parser.add_argument("base", type=Path)
    capture_parser.add_argument("overlay", type=Path)

    arguments = parser.parse_args()
    if arguments.command == "render":
        render(arguments.base, arguments.overlay, arguments.output)
    else:
        capture(arguments.local, arguments.base, arguments.overlay)


if __name__ == "__main__":
    main()
