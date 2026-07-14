#!/usr/bin/env python3
"""Assert CLI contract stays aligned with MCP schemas, man pages, and bash completions.

Usage: python3 scripts/ci/check-cli-contract.py
Prefer: make check-cli-contract
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "spec" / "cli-contract.yaml"
MCP = ROOT / "scripts" / "millennium-mcp.py"
BASH_COMP = ROOT / "completions" / "bash" / "millennium-helpers"
MAN_DIR = ROOT / "man"


def fail(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(1)


def load_contract() -> dict:
    try:
        import yaml  # type: ignore
    except ImportError:
        fail("PyYAML is required (pip install pyyaml) for check-cli-contract")

    if not CONTRACT.is_file():
        fail(f"missing contract: {CONTRACT.relative_to(ROOT)}")
    data = yaml.safe_load(CONTRACT.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        fail("cli-contract.yaml must be a mapping")
    return data


def check_dispatcher(contract: dict) -> None:
    dispatcher = contract.get("dispatcher") or {}
    cmds = dispatcher.get("commands")
    if not isinstance(cmds, list) or not cmds:
        fail("dispatcher.commands must be a non-empty list")
    commands = contract.get("commands") or {}
    for c in cmds:
        if c not in commands:
            fail(f"dispatcher command {c!r} missing from commands:")


def check_man(contract: dict) -> None:
    commands = contract.get("commands") or {}
    for name, meta in commands.items():
        if not isinstance(meta, dict):
            continue
        man = meta.get("man")
        if not man:
            continue
        path = MAN_DIR / man
        if not path.is_file():
            fail(f"command {name!r}: missing man page {path.relative_to(ROOT)}")


def mcp_tool_blocks(src: str) -> dict[str, set[str]]:
    """Map MCP tool name -> set of inputSchema property names."""
    tools: dict[str, set[str]] = {}
    # Match each tools/list entry by name, then take the following inputSchema object.
    for m in re.finditer(r'"name":\s*"(millennium_\w+)"', src):
        name = m.group(1)
        rest = src[m.end() : m.end() + 2500]
        schema_m = re.search(r'"inputSchema":\s*\{', rest)
        if not schema_m:
            tools[name] = set()
            continue
        start = schema_m.end() - 1  # at '{'
        depth = 0
        end = None
        for i, ch in enumerate(rest[start:]):
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    end = start + i + 1
                    break
        schema = rest[start:end] if end else ""
        props = set(re.findall(r'"([a-z_]+)":\s*\{\s*"type":', schema))
        tools[name] = props
    return tools


def check_mcp(contract: dict) -> None:
    if not MCP.is_file():
        fail(f"missing MCP server: {MCP.relative_to(ROOT)}")
    src = MCP.read_text(encoding="utf-8")
    tools = mcp_tool_blocks(src)
    if not tools:
        fail("no MCP tools parsed from millennium-mcp.py")
    commands = contract.get("commands") or {}
    for name, meta in commands.items():
        if not isinstance(meta, dict):
            continue
        mcp_name = meta.get("mcp")
        if not mcp_name:
            continue
        if mcp_name not in tools:
            fail(
                f"command {name!r}: MCP tool {mcp_name!r} not found in millennium-mcp.py"
            )
        expected = meta.get("mcp_properties")
        if expected is None:
            continue
        found = tools[mcp_name]
        for prop in expected:
            if prop not in found:
                fail(
                    f"command {name!r}: MCP tool {mcp_name!r} missing property {prop!r} "
                    f"(have {sorted(found)})"
                )


def check_completions(contract: dict) -> None:
    if not BASH_COMP.is_file():
        fail(f"missing bash completions: {BASH_COMP.relative_to(ROOT)}")
    text = BASH_COMP.read_text(encoding="utf-8")
    dispatcher = (contract.get("dispatcher") or {}).get("commands") or []
    # Top-level millennium completer should list feature commands.
    for cmd in dispatcher:
        if cmd in ("help", "doctor", "mcp"):
            # doctor is alias; mcp may be completed via binary name only
            continue
        if cmd not in text:
            fail(f"bash completions missing dispatcher command {cmd!r}")

    commands = contract.get("commands") or {}
    for name, meta in commands.items():
        if not isinstance(meta, dict):
            continue
        binary = meta.get("binary")
        if binary and f"millennium-{name}" not in text and binary not in text:
            # Some commands share the millennium-helpers completer file via binary name.
            if binary not in text:
                fail(f"bash completions missing binary reference {binary!r}")

        for flag in meta.get("flags") or []:
            if not isinstance(flag, dict):
                continue
            long = flag.get("long")
            if not long or flag.get("os_only"):
                continue
            # Flag should appear somewhere in bash completions for its command family.
            if long not in text:
                # Global-ish flags may only appear on some binaries; require on major cmds.
                if name in ("upgrade", "schedule", "diag", "theme", "repair", "purge"):
                    fail(
                        f"bash completions missing flag {long!r} (from command {name})"
                    )


def main() -> None:
    contract = load_contract()
    check_dispatcher(contract)
    check_man(contract)
    check_mcp(contract)
    check_completions(contract)
    print("cli-contract: OK")


if __name__ == "__main__":
    main()
