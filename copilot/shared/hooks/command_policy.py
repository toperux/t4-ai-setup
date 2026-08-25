#!/usr/bin/env python3
"""Block prohibited shell commands before Copilot executes them."""

import json
import re
import sys


GIT_PUSH = re.compile(r"(?<![\w-])git\s+push(?:\s|$)", re.IGNORECASE)
CD = re.compile(r"(?:^|[;&|]\s*)cd(?:\s|$)", re.IGNORECASE)


def deny(reason):
    json.dump(
        {
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        },
        sys.stdout,
    )


def main():
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        deny("Could not inspect the shell command.")
        return

    command = (payload.get("tool_input") or {}).get("command") or ""
    if GIT_PUSH.search(command):
        deny("`git push` is blocked by your user-level policy.")
    elif CD.search(command):
        deny("`cd` is blocked. Use a tool-specific directory option or absolute write paths.")
    else:
        print("{}")


if __name__ == "__main__":
    main()
