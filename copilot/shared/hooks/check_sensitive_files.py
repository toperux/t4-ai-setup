#!/usr/bin/env python3
"""Block Copilot file operations that target sensitive configuration or key files."""

import json
import os
import sys


PATH_KEYS = {"file", "file_path", "filepath", "path", "paths", "target", "target_path"}
SENSITIVE_NAMES = {
    "appsettings.json",
    "web.config",
    "local.settings.json",
}


def deny(reason):
    json.dump(
        {
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        },
        sys.stdout,
    )


def candidate_paths(value, key=""):
    if isinstance(value, dict):
        for child_key, child_value in value.items():
            yield from candidate_paths(child_value, child_key.lower())
    elif isinstance(value, list):
        for item in value:
            yield from candidate_paths(item, key)
    elif isinstance(value, str) and key in PATH_KEYS:
        yield value


def is_sensitive(path):
    normalized = path.replace("\\", "/").lower()
    name = os.path.basename(normalized)
    return (
        name == ".env"
        or name.startswith(".env.")
        or name.endswith(".pem")
        or name.endswith(".key")
        or name in SENSITIVE_NAMES
        or name.startswith("appsettings.") and name.endswith(".json")
        or "/secrets/" in normalized
        or "secrets" in name
    )


def main():
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        deny("Could not inspect the tool request for sensitive-file access.")
        return

    tool_name = payload.get("tool_name", "")
    if tool_name not in {"Read", "Edit", "Write"}:
        print("{}")
        return

    tool_input = payload.get("tool_input") or {}
    for path in candidate_paths(tool_input):
        if is_sensitive(path):
            deny(
                "Sensitive files (.env, keys, secrets, appsettings, web.config, and "
                "local.settings.json) are off-limits."
            )
            return

    print("{}")


if __name__ == "__main__":
    main()
