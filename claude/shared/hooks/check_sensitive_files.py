#!/usr/bin/env python3
"""
PreToolUse hook for Claude Code.
Blocks Read/Edit/Write on sensitive files (secrets, .env, ASP.NET and
Azure Functions configs) regardless of what the permissions.deny rules
in settings.json say. Exit code 2 blocks the tool call and returns
the stderr message to Claude as the reason.
"""

import json
import sys
import fnmatch
import os

# Glob patterns are matched against the file's normalized path using
# fnmatch, checked against both the full path and the basename so this
# works whether Claude passes an absolute or relative path.
SENSITIVE_PATTERNS = [
    ".env",
    ".env.*",
    "*.pem",
    "*.key",
    "*secrets*",
    "appsettings.json",
    "appsettings.*.json",
    "web.config",
    "local.settings.json",
]

BLOCKED_TOOLS = {"Read", "Edit", "Write"}


def is_sensitive(path: str) -> bool:
    norm = path.replace("\\", "/")
    base = os.path.basename(norm)
    for pattern in SENSITIVE_PATTERNS:
        if fnmatch.fnmatch(base, pattern):
            return True
        if fnmatch.fnmatch(norm, f"*{pattern}"):
            return True
        if fnmatch.fnmatch(norm, f"*/{pattern}"):
            return True
    return False


def main():
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        # If we can't parse input, fail safe by allowing (don't break the session).
        sys.exit(0)

    tool_name = payload.get("tool_name", "")
    tool_input = payload.get("tool_input", {}) or {}

    if tool_name not in BLOCKED_TOOLS:
        sys.exit(0)

    # Read/Edit/Write all use file_path as the parameter name.
    file_path = tool_input.get("file_path", "")

    if file_path and is_sensitive(file_path):
        sys.stderr.write(
            f"Blocked: '{file_path}' matches a sensitive-file pattern "
            f"(secrets/.env/appsettings/web.config/local.settings.json). "
            f"This file is off-limits to {tool_name}.\n"
        )
        sys.exit(2)  # 2 = block the tool call, message goes back to Claude

    sys.exit(0)  # allow


if __name__ == "__main__":
    main()
