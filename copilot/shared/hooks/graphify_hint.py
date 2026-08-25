#!/usr/bin/env python3
"""Suggest graph queries before broad source searches in graphified repositories."""

import json
import os
import re
import sys


SEARCH_COMMAND = re.compile(r"\b(?:grep|rg|ripgrep|find|fd|ack|ag)\b", re.IGNORECASE)
CONTEXT = (
    "graphify: knowledge graph at graphify-out/. For focused questions, run "
    '`graphify query "<question>"` (scoped subgraph) instead of searching raw files. '
    "Read GRAPH_REPORT.md only for broad architecture context."
)


def main():
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        print("{}")
        return

    cwd = payload.get("cwd") or os.getcwd()
    if not os.path.isfile(os.path.join(cwd, "graphify-out", "graph.json")):
        print("{}")
        return

    tool_name = payload.get("tool_name", "")
    command = (payload.get("tool_input") or {}).get("command") or ""
    if tool_name in {"Grep", "Glob"} or SEARCH_COMMAND.search(command):
        print(json.dumps({"additionalContext": CONTEXT}))
    else:
        print("{}")


if __name__ == "__main__":
    main()
