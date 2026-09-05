#!/usr/bin/env python3
"""Deny `git worktree add` outside approved roots.

PreToolUse/Bash hook. Approved: <cwd>/.claude/worktrees/ (gitignored by convention)
and <temp>/claude/. Anything else -> deny, so worktrees stop landing in the
workspace root or C:\\.
"""
import json
import os
import shlex
import sys
import tempfile

# `git worktree add` options that consume the following token
VALUED = {"-b", "-B", "--reason"}
MSYS_DRIVE = 2  # "/c/..." -> drive letter at index 1


def win(path):
    """Translate an MSYS path (/c/Users/...) to a native one."""
    if len(path) > MSYS_DRIVE and path[0] == "/" and path[MSYS_DRIVE] == "/" and path[1].isalpha():
        return path[1] + ":/" + path[MSYS_DRIVE + 1:]
    return path


def norm(path, cwd):
    path = win(path)
    if not os.path.isabs(path):
        path = os.path.join(cwd, path)
    return os.path.normcase(os.path.normpath(path))


def roots(cwd):
    return [
        norm(os.path.join(cwd, ".claude", "worktrees"), cwd),
        norm(os.path.join(tempfile.gettempdir(), "claude"), cwd),
    ]


def under(target, root):
    return target == root or target.startswith(root + os.sep)


def targets(command):
    """Target path of each `git worktree add` in the command; None if unparseable."""
    # Non-POSIX on Windows: POSIX mode eats backslashes, so C:\a\b becomes C:ab.
    # It keeps the quotes, hence the strip on the target below.
    try:
        toks = shlex.split(command, posix=os.name != "nt")
    except ValueError:
        toks = command.split()
    found = []
    for i in range(len(toks) - 1):
        if toks[i] != "worktree" or toks[i + 1] != "add":
            continue
        j = i + 2
        while j < len(toks):
            t = toks[j]
            if t in VALUED:
                j += 2
                continue
            if t.startswith("-"):
                j += 1
                continue
            break
        found.append(toks[j].strip("\"'") if j < len(toks) else None)
    return found


def deny(reason):
    json.dump({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}, sys.stdout)
    sys.exit(0)


def main():
    try:
        data = json.load(sys.stdin)
    except (ValueError, OSError):
        return
    command = (data.get("tool_input") or {}).get("command") or ""
    if "worktree" not in command:
        return
    cwd = data.get("cwd") or os.getcwd()
    allowed = roots(cwd)
    for target in targets(command):
        if target is None:
            deny("`git worktree add` with no parseable target path. Pass an explicit "
                 "path under .claude/worktrees/ or %s." % allowed[1])
        resolved = norm(target, cwd)
        if not any(under(resolved, r) for r in allowed):
            deny("Worktree location not allowed: %s. Create worktrees under "
                 "%s or %s." % (resolved, allowed[0], allowed[1]))


main()
