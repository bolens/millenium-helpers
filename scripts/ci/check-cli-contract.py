#!/usr/bin/env python3
"""Assert CLI contract stays aligned with MCP schemas, man pages, and completions.

Usage:
  python3 scripts/ci/check-cli-contract.py
  python3 scripts/ci/check-cli-contract.py --list-man-bases
Prefer: make check-cli-contract
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "spec" / "cli-contract.yaml"
MCP = ROOT / "go" / "internal" / "mcp" / "tools.go"
MAN_DIR = ROOT / "man"

COMPLETION_SOURCES: dict[str, Path] = {
    "bash": ROOT / "completions" / "bash" / "millennium-helpers",
    "zsh": ROOT / "completions" / "zsh" / "_millennium-helpers",
    "fish": ROOT / "completions" / "fish" / "millennium.fish",
    "nushell": ROOT / "completions" / "nushell" / "millennium-helpers.nu",
    "powershell": ROOT / "completions" / "powershell" / "millennium-helpers.ps1",
}


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


def contract_man_bases(contract: dict) -> list[str]:
    """Unique man page basenames from contract commands.*.man (without .1)."""
    bases: list[str] = []
    seen: set[str] = set()
    for _name, meta in (contract.get("commands") or {}).items():
        if not isinstance(meta, dict):
            continue
        man = meta.get("man")
        if not man or not isinstance(man, str):
            continue
        base = man[:-2] if man.endswith(".1") else man
        if base not in seen:
            seen.add(base)
            bases.append(base)
    return bases


def check_dispatcher(contract: dict) -> None:
    dispatcher = contract.get("dispatcher") or {}
    cmds = dispatcher.get("commands")
    if not isinstance(cmds, list) or not cmds:
        fail("dispatcher.commands must be a non-empty list")
    commands = contract.get("commands") or {}
    for c in cmds:
        if c not in commands:
            fail(f"dispatcher command {c!r} missing from commands:")


def man_has_flag(page_text: str, long_flag: str) -> bool:
    """Match --flag in man sources (plain or troff-escaped \\-\\-dry\\-run)."""
    if long_flag in page_text:
        return True
    bare = long_flag.removeprefix("--")
    # troff often escapes every hyphen: \-\-dry\-run
    escaped = "\\-\\-" + bare.replace("-", "\\-")
    if escaped in page_text:
        return True
    # partial escape: \-\-dry-run
    if f"\\-\\-{bare}" in page_text:
        return True
    return False


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
        text = path.read_text(encoding="utf-8")
        for flag in meta.get("flags") or []:
            if not isinstance(flag, dict):
                continue
            long = flag.get("long")
            if not long or flag.get("os_only"):
                continue
            # help/version appear on almost every page; still require them.
            if not man_has_flag(text, long):
                fail(
                    f"command {name!r}: man page {man} missing flag {long!r} "
                    f"(expected {long} or troff \\-\\- form)"
                )


def mcp_tool_blocks(src: str) -> dict[str, dict[str, object]]:
    """Map MCP tool name -> {props: set[str], enums: dict[str, list[str]]}."""
    tools: dict[str, dict[str, object]] = {}
    for m in re.finditer(r'Name:\s+"(millennium_\w+)"', src):
        name = m.group(1)
        rest = src[m.end() : m.end() + 3500]
        schema_m = re.search(r"InputSchema:\s*map\[string\]any\{", rest)
        if not schema_m:
            tools[name] = {"props": set(), "enums": {}}
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
        props = set(re.findall(r'"([a-z_]+)":\s*map\[string\]any\{', schema))
        props.discard("properties")
        enums: dict[str, list[str]] = {}
        # Go catalog uses: "action": map[string]any{ ... "enum": []string{"a","b"}, ...}
        for prop_m in re.finditer(
            r'"([a-z_]+)":\s*map\[string\]any\{',
            schema,
        ):
            prop = prop_m.group(1)
            if prop == "properties":
                continue
            block_start = prop_m.end() - 1
            depth = 0
            block_end = None
            for i, ch in enumerate(schema[block_start:]):
                if ch == "{":
                    depth += 1
                elif ch == "}":
                    depth -= 1
                    if depth == 0:
                        block_end = block_start + i + 1
                        break
            block = schema[block_start:block_end] if block_end else ""
            enum_m = re.search(
                r'"enum":\s*\[\]string\{([^}]*)\}',
                block,
            )
            if enum_m:
                enums[prop] = re.findall(r'"([^"]+)"', enum_m.group(1))
        tools[name] = {"props": props, "enums": enums}
    return tools


def check_mcp(contract: dict) -> None:
    if not MCP.is_file():
        fail(f"missing MCP tools catalog: {MCP.relative_to(ROOT)}")
    src = MCP.read_text(encoding="utf-8")
    tools = mcp_tool_blocks(src)
    if not tools:
        fail("no MCP tools parsed from go/internal/mcp/tools.go")
    commands = contract.get("commands") or {}
    for name, meta in commands.items():
        if not isinstance(meta, dict):
            continue
        mcp_name = meta.get("mcp")
        if not mcp_name:
            continue
        if mcp_name not in tools:
            fail(
                f"command {name!r}: MCP tool {mcp_name!r} not found in go/internal/mcp/tools.go"
            )
        expected = meta.get("mcp_properties")
        if expected is None:
            continue
        found = tools[mcp_name]["props"]
        assert isinstance(found, set)
        for prop in expected:
            if prop not in found:
                fail(
                    f"command {name!r}: MCP tool {mcp_name!r} missing property {prop!r} "
                    f"(have {sorted(found)})"
                )
        # Optional tighter surface for MCP action enums (schedule, …).
        mcp_actions = meta.get("mcp_actions")
        if mcp_actions is not None:
            enums = tools[mcp_name]["enums"]
            assert isinstance(enums, dict)
            action_enum = enums.get("action")
            if not action_enum:
                fail(f"command {name!r}: MCP tool {mcp_name!r} missing action enum")
            for action in mcp_actions:
                if action not in action_enum:
                    fail(
                        f"command {name!r}: MCP action enum missing {action!r} "
                        f"(have {action_enum})"
                    )


def check_completions(contract: dict) -> None:
    texts: dict[str, str] = {}
    for shell, path in COMPLETION_SOURCES.items():
        if not path.is_file():
            fail(f"missing {shell} completions: {path.relative_to(ROOT)}")
        texts[shell] = path.read_text(encoding="utf-8")

    bash = texts["bash"]
    if "complete -F" not in bash or re.search(r"\bmillennium\b", bash) is None:
        fail("bash completions must register the millennium dispatcher")

    dispatcher = (contract.get("dispatcher") or {}).get("commands") or []
    for cmd in dispatcher:
        if cmd == "help":
            continue
        for shell, text in texts.items():
            if cmd not in text:
                fail(f"{shell} completions missing dispatcher command {cmd!r}")

    commands = contract.get("commands") or {}
    for name, meta in commands.items():
        if not isinstance(meta, dict):
            continue

        for sub in meta.get("subcommands") or []:
            if sub not in bash:
                fail(f"bash completions missing subcommand {sub!r} (from {name})")

        for flag in meta.get("flags") or []:
            if not isinstance(flag, dict):
                continue
            long = flag.get("long")
            if not long or flag.get("os_only"):
                continue
            if long not in bash:
                fail(f"bash completions missing flag {long!r} (from command {name})")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--list-man-bases",
        action="store_true",
        help="Print contract man page basenames (one per line) and exit",
    )
    args = parser.parse_args()
    contract = load_contract()
    if args.list_man_bases:
        for base in contract_man_bases(contract):
            print(base)
        return

    check_dispatcher(contract)
    check_man(contract)
    check_mcp(contract)
    check_completions(contract)
    print("cli-contract: OK")


if __name__ == "__main__":
    main()
