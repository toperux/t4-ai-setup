#!/usr/bin/env python3
"""Allow `git worktree add` only below approved locations."""

import json
import os
import shlex
import sys
import tempfile


VALUED_OPTIONS = {"-b", "-B", "--reason"}


def deny(reason):
    json.dump(
        {
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        },
        sys.stdout,
    )


def windows_path(path):
    if len(path) > 2 and path[0] == "/" and path[2] == "/" and path[1].isalpha():
        return path[1] + ":/" + path[3:]
    return path


def normalize(path, cwd):
    path = windows_path(path)
    if not os.path.isabs(path):
        path = os.path.join(cwd, path)
    return os.path.normcase(os.path.normpath(path))


def approved_roots(cwd):
    return [
        normalize(os.path.join(cwd, ".copilot", "worktrees"), cwd),
        normalize(os.path.join(tempfile.gettempdir(), "copilot"), cwd),
    ]


def is_under(path, root):
    return path == root or path.startswith(root + os.sep)


def worktree_targets(command):
    try:
        tokens = shlex.split(command, posix=os.name != "nt")
    except ValueError:
        tokens = command.split()

    targets = []
    for index in range(len(tokens) - 1):
        if tokens[index] != "worktree" or tokens[index + 1] != "add":
            continue

        target_index = index + 2
        while target_index < len(tokens):
            token = tokens[target_index]
            if token in VALUED_OPTIONS:
                target_index += 2
            elif token.startswith("-"):
                target_index += 1
            else:
                break
        targets.append(
            tokens[target_index].strip("\"'")
            if target_index < len(tokens)
            else None
        )
    return targets


def main():
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        deny("Could not inspect the git worktree request.")
        return

    command = (payload.get("tool_input") or {}).get("command") or ""
    if "worktree" not in command:
        print("{}")
        return

    cwd = payload.get("cwd") or os.getcwd()
    roots = approved_roots(cwd)
    for target in worktree_targets(command):
        if target is None:
            deny(
                "`git worktree add` requires an explicit path under .copilot/worktrees "
                f"or {roots[1]}."
            )
            return

        resolved = normalize(target, cwd)
        if not any(is_under(resolved, root) for root in roots):
            deny(
                f"Worktree location not allowed: {resolved}. Create worktrees under "
                f"{roots[0]} or {roots[1]}."
            )
            return

    print("{}")


if __name__ == "__main__":
    main()
