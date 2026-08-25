#!/usr/bin/env python3
"""Remind Copilot to refresh a graphify graph after source edits."""

import json
import os
import sys


def main():
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        print("{}")
        return

    cwd = payload.get("cwd") or os.getcwd()
    graph = os.path.join(cwd, "graphify-out", "graph.json")
    if os.path.isfile(graph):
        print(
            json.dumps(
                {
                    "additionalContext": (
                        "graphify: source changed. Run `graphify update .` after edits "
                        "to keep the graph current."
                    )
                }
            )
        )
    else:
        print("{}")


if __name__ == "__main__":
    main()
