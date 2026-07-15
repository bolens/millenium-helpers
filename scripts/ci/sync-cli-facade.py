#!/usr/bin/env python3
"""Sync marked façade regions from spec/cli-contract.yaml.

Marked blocks use:
  # @@cli-contract:<key>@@
  ... generated ...
  # @@/cli-contract:<key>@@

(Comment prefix may also be `.\\\" ` for man, or `// ` for Go.)

Keys:
  dispatcher.commands
  commands.<name>.subcommands
  commands.<name>.flags
  commands.install_uninstall.flags   # bash shared install|uninstall completer
  commands.<name>.man_options
  channels
  mcp.tools
  mcp.dispatch_allowlists

Usage:
  python3 scripts/ci/sync-cli-facade.py          # write
  python3 scripts/ci/sync-cli-facade.py --check  # CI: fail if dirty
Prefer: make sync-cli-facade / make check-cli-contract
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "spec" / "cli-contract.yaml"

TARGETS = [
    ROOT / "completions" / "bash" / "millennium-helpers",
    ROOT / "completions" / "zsh" / "_millennium-helpers",
    ROOT / "completions" / "fish" / "millennium.fish",
    ROOT / "completions" / "nushell" / "millennium-helpers.nu",
    ROOT / "completions" / "powershell" / "millennium-helpers.ps1",
    ROOT / "man" / "millennium-diag.1",
    ROOT / "man" / "millennium-upgrade.1",
    ROOT / "man" / "millennium-schedule.1",
    ROOT / "man" / "millennium-theme.1",
    ROOT / "man" / "millennium-repair.1",
    ROOT / "man" / "millennium-purge.1",
    ROOT / "man" / "millennium-mcp.1",
    ROOT / "go" / "internal" / "mcp" / "tools.go",
    ROOT / "go" / "internal" / "mcp" / "dispatch.go",
]

# Preserve historical tools/list order for MCP clients.
MCP_TOOL_ORDER = ["diag", "theme", "upgrade", "schedule", "repair", "purge"]


def fail(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(1)


def load_contract() -> dict:
    try:
        import yaml  # type: ignore
    except ImportError:
        fail("PyYAML is required (pip install pyyaml) for sync-cli-facade")
    if not CONTRACT.is_file():
        fail(f"missing contract: {CONTRACT.relative_to(ROOT)}")
    data = yaml.safe_load(CONTRACT.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        fail("cli-contract.yaml must be a mapping")
    return data


def marker_re(key: str) -> re.Pattern[str]:
    # Comment prefix may be "# " or "" (already inside a comment line).
    return re.compile(
        rf"(?P<prefix>[^\n]*?)@@cli-contract:{re.escape(key)}@@\n"
        rf"(?P<body>.*?)"
        rf"(?P=prefix)@@/cli-contract:{re.escape(key)}@@",
        re.DOTALL,
    )


def flag_tokens(flags: object) -> list[str]:
    """Ordered completion tokens: short then long for each flag."""
    if not isinstance(flags, list):
        return []
    out: list[str] = []
    seen: set[str] = set()
    for item in flags:
        if not isinstance(item, dict):
            continue
        for key in ("short", "long"):
            tok = item.get(key)
            if isinstance(tok, str) and tok and tok not in seen:
                seen.add(tok)
                out.append(tok)
    return out


def command_flags(commands: dict, name: str) -> list[str]:
    meta = commands.get(name) or {}
    if not isinstance(meta, dict):
        fail(f"commands.{name} missing")
    tokens = flag_tokens(meta.get("flags"))
    if not tokens:
        fail(f"commands.{name}.flags empty")
    return tokens


def render_flag_body(tokens: list[str], path: Path) -> str:
    name = path.name
    if name == "millennium-helpers" and "bash" in str(path):
        return f'  local flagopts="{" ".join(tokens)}"\n'
    if name == "millennium-helpers.ps1":
        inner = ", ".join(f"'{t}'" for t in tokens)
        return f"    @({inner})\n"
    fail(f"no flag renderer for {path.relative_to(ROOT)}")


def troff_flag(tok: str) -> str:
    return tok.replace("-", r"\-")


def man_arg_suffix(arg: str) -> str:
    if arg.startswith("[") and arg.endswith("]"):
        inner = arg[1:-1]
        return f' " [" \\fI{inner}\\fR "]"'
    return f' " " \\fI{arg}\\fR'


def render_man_options(meta: dict, cmd: str) -> str:
    flags = meta.get("flags") or []
    if not isinstance(flags, list) or not flags:
        fail(f"commands.{cmd}.flags required for man_options sync")
    lines: list[str] = []
    for flag in flags:
        if not isinstance(flag, dict):
            continue
        long = flag.get("long")
        if not isinstance(long, str) or not long:
            fail(f"commands.{cmd}: flag missing long")
        short = flag.get("short")
        arg = flag.get("arg")
        man = flag.get("man")
        if not isinstance(man, str) or not man.strip():
            fail(f"commands.{cmd}: flag {long!r} missing man: description")
        suffix = man_arg_suffix(arg) if isinstance(arg, str) and arg else ""
        if isinstance(short, str) and short:
            lines.append(
                f'.TP\n.BR {troff_flag(short)} ", " {troff_flag(long)}{suffix}'
            )
        elif suffix:
            lines.append(f".TP\n.BR {troff_flag(long)}{suffix}")
        else:
            lines.append(f".TP\n.B {troff_flag(long)}")
        for raw in man.strip().splitlines():
            lines.append(raw.rstrip())
    return "\n".join(lines) + "\n"


def resolve_mcp_enum(
    spec: dict, meta: dict, contract: dict, cmd: str, prop: str
) -> list[str] | None:
    enum = spec.get("enum")
    if enum is None:
        return None
    if enum == "channels":
        channels = contract.get("channels") or []
        if not channels:
            fail("channels empty")
        return list(channels)
    if enum == "mcp_actions":
        actions = meta.get("mcp_actions")
        if not actions:
            fail(
                f"commands.{cmd}: mcp_schema.{prop}.enum is mcp_actions but mcp_actions missing"
            )
        return list(actions)
    if enum == "subcommands":
        subs = meta.get("subcommands")
        if not subs:
            fail(
                f"commands.{cmd}: mcp_schema.{prop}.enum is subcommands but subcommands missing"
            )
        return list(subs)
    if isinstance(enum, list):
        return [str(x) for x in enum]
    fail(f"commands.{cmd}: mcp_schema.{prop}.enum unsupported: {enum!r}")


def render_mcp_dispatch_allowlists(contract: dict) -> str:
    commands = contract.get("commands") or {}
    theme = commands.get("theme") or {}
    schedule = commands.get("schedule") or {}
    if not isinstance(theme, dict) or not isinstance(schedule, dict):
        fail("commands.theme and commands.schedule required for MCP dispatch sync")
    theme_actions = theme.get("mcp_actions") or theme.get("subcommands")
    schedule_actions = schedule.get("mcp_actions")
    channels = contract.get("channels") or []
    if not theme_actions:
        fail(
            "commands.theme.mcp_actions (or subcommands) required for MCP dispatch sync"
        )
    if not schedule_actions:
        fail("commands.schedule.mcp_actions required for MCP dispatch sync")
    if not channels:
        fail("channels empty")

    rows = [
        ("validThemeActions", [str(x) for x in theme_actions]),
        ("validScheduleActions", [str(x) for x in schedule_actions]),
        ("validChannels", [str(x) for x in channels]),
    ]
    width = max(len(name) for name, _ in rows)
    lines: list[str] = []
    for name, values in rows:
        inner = ", ".join(f"{json.dumps(v)}: true" for v in values)
        lines.append(f"\t{name.ljust(width)} = map[string]bool{{{inner}}}")
    return "\n".join(lines) + "\n"


def render_mcp_tools(contract: dict) -> str:
    commands = contract.get("commands") or {}
    names = [n for n in MCP_TOOL_ORDER if n in commands]
    for name, meta in commands.items():
        if not isinstance(meta, dict):
            continue
        if meta.get("mcp") and name not in names:
            names.append(name)

    chunks: list[str] = []
    for name in names:
        meta = commands.get(name)
        if not isinstance(meta, dict):
            continue
        tool = meta.get("mcp")
        if not tool:
            continue
        desc = meta.get("mcp_description")
        if not isinstance(desc, str) or not desc.strip():
            fail(f"commands.{name}: mcp_description required for MCP façade sync")
        desc = " ".join(desc.split())
        props_list = meta.get("mcp_properties")
        if props_list is None:
            fail(f"commands.{name}: mcp_properties required for MCP façade sync")
        schema = meta.get("mcp_schema") or {}
        if not isinstance(schema, dict):
            fail(f"commands.{name}: mcp_schema must be a mapping")
        for prop in props_list:
            if prop not in schema:
                fail(f"commands.{name}: mcp_schema missing property {prop!r}")

        lines = [
            "\t\t{",
            f"\t\t\tName:        {json.dumps(tool)},",
            f"\t\t\tDescription: {json.dumps(desc)},",
            "\t\t\tInputSchema: map[string]any{",
            '\t\t\t\t"type": "object",',
        ]
        if props_list:
            lines.append('\t\t\t\t"properties": map[string]any{')
            for prop in props_list:
                spec = schema[prop]
                if not isinstance(spec, dict):
                    fail(f"commands.{name}: mcp_schema.{prop} must be a mapping")
                ptype = spec.get("type")
                pdesc = spec.get("description")
                if not isinstance(ptype, str) or not ptype:
                    fail(f"commands.{name}: mcp_schema.{prop}.type required")
                if not isinstance(pdesc, str) or not pdesc.strip():
                    fail(f"commands.{name}: mcp_schema.{prop}.description required")
                pdesc = " ".join(pdesc.split())
                lines.append(f"\t\t\t\t\t{json.dumps(prop)}: map[string]any{{")
                lines.append(f'\t\t\t\t\t\t"type":        {json.dumps(ptype)},')
                enum_vals = resolve_mcp_enum(spec, meta, contract, name, prop)
                if enum_vals is not None:
                    enum_lit = ", ".join(json.dumps(v) for v in enum_vals)
                    lines.append(f'\t\t\t\t\t\t"enum":        []string{{{enum_lit}}},')
                lines.append(f'\t\t\t\t\t\t"description": {json.dumps(pdesc)},')
                lines.append("\t\t\t\t\t},")
            lines.append("\t\t\t\t},")
        else:
            lines.append('\t\t\t\t"properties": map[string]any{},')
        required = meta.get("mcp_required")
        if required:
            req_lit = ", ".join(json.dumps(str(r)) for r in required)
            lines.append(f'\t\t\t\t"required": []string{{{req_lit}}},')
        lines.append("\t\t\t},")
        lines.append("\t\t},")
        chunks.append("\n".join(lines))
    if not chunks:
        fail("no MCP tools to sync")
    return "\n".join(chunks) + "\n"


def render_key(contract: dict, key: str, path: Path) -> str:
    """Return the body (no marker lines) for a key in a given file."""
    name = path.name
    commands = contract.get("commands") or {}

    if key == "dispatcher.commands":
        cmds = (contract.get("dispatcher") or {}).get("commands") or []
        if not cmds:
            fail("dispatcher.commands empty")
        if name == "millennium-helpers" and "bash" in str(path):
            return f'    COMPREPLY=( $(compgen -W "{" ".join(cmds)}" -- "${{cur}}") )\n'
        if name == "_millennium-helpers":
            lines = ["  cmds=("]
            for c in cmds:
                meta = commands.get(c) or {}
                short = meta.get("short") if isinstance(meta, dict) else None
                if not short:
                    fail(f"commands.{c}.short is required for zsh façade sync")
                # Escape single quotes for zsh 'cmd:desc' form.
                desc = str(short).replace("'", "'\\''")
                lines.append(f"    '{c}:{desc}'")
            lines.append("  )")
            return "\n".join(lines) + "\n"
        if name == "millennium.fish":
            return f"set -l __mh_cmds {' '.join(cmds)}\n"
        if name == "millennium-helpers.nu":
            inner = ", ".join(f'"{c}"' for c in cmds)
            return f"  [ {inner} ]\n"
        if name == "millennium-helpers.ps1":
            inner = ", ".join(f"'{c}'" for c in cmds)
            return f"    @({inner})\n"
        fail(f"no renderer for dispatcher.commands in {path.relative_to(ROOT)}")

    if key == "channels":
        channels = contract.get("channels") or []
        if not channels:
            fail("channels empty")
        if name == "millennium-helpers" and "bash" in str(path):
            return f'  local channels="{" ".join(channels)}"\n'
        if name == "millennium-helpers.ps1":
            inner = ", ".join(f"'{c}'" for c in channels)
            return f"    @({inner})\n"
        if name == "millennium-helpers.nu":
            # Nushell schedule completer also offers config verbs; keep them after channels.
            inner = ", ".join(f'"{c}"' for c in channels)
            return f'  [ {inner}, "get", "set", "list" ]\n'
        fail(f"no renderer for channels in {path.relative_to(ROOT)}")

    if key == "commands.install_uninstall.flags":
        tokens: list[str] = []
        seen: set[str] = set()
        for cmd in ("install", "uninstall"):
            for tok in command_flags(commands, cmd):
                if tok not in seen:
                    seen.add(tok)
                    tokens.append(tok)
        return render_flag_body(tokens, path)

    if key == "mcp.tools":
        if path.name != "tools.go":
            fail(
                f"mcp.tools only valid in go/internal/mcp/tools.go (got {path.relative_to(ROOT)})"
            )
        return render_mcp_tools(contract)

    if key == "mcp.dispatch_allowlists":
        if path.name != "dispatch.go":
            fail(
                "mcp.dispatch_allowlists only valid in go/internal/mcp/dispatch.go "
                f"(got {path.relative_to(ROOT)})"
            )
        return render_mcp_dispatch_allowlists(contract)

    m = re.fullmatch(r"commands\.([a-z_]+)\.man_options", key)
    if m:
        cmd = m.group(1)
        meta = commands.get(cmd) or {}
        if not isinstance(meta, dict):
            fail(f"commands.{cmd} missing")
        if path.suffix != ".1":
            fail(f"{key} only valid in man pages")
        return render_man_options(meta, cmd)

    m = re.fullmatch(r"commands\.([a-z_]+)\.flags", key)
    if m:
        tokens = command_flags(commands, m.group(1))
        return render_flag_body(tokens, path)

    m = re.fullmatch(r"commands\.([a-z_]+)\.subcommands", key)
    if m:
        cmd = m.group(1)
        meta = commands.get(cmd) or {}
        if not isinstance(meta, dict):
            fail(f"commands.{cmd} missing")
        subs = meta.get("subcommands") or []
        if not subs:
            fail(f"commands.{cmd}.subcommands empty")
        if name == "millennium-helpers" and "bash" in str(path):
            return f'  local subcmds="{" ".join(subs)}"\n'
        if name == "_millennium-helpers":
            if cmd == "schedule":
                return f"                '1:command:({' '.join(subs)})' \\\n"
            if cmd == "theme":
                return f"                '1:command:({' '.join(subs)})' \\\n"
            if cmd == "diag":
                return f"                '1:command:({' '.join(subs)})' \\\n"
        if name == "millennium.fish":
            if cmd == "schedule":
                return (
                    "complete -c millennium -f -n '__fish_seen_subcommand_from schedule' "
                    f"-a '{' '.join(subs)}' -d 'Schedule command'\n"
                )
            if cmd == "theme":
                return (
                    "complete -c millennium -f -n '__fish_seen_subcommand_from theme' "
                    f"-a '{' '.join(subs)}' -d 'Theme command'\n"
                )
            if cmd == "diag":
                # two -a lines exist for doctor/logs; regenerate both from subcommands
                lines = []
                descs = {
                    "doctor": "Repair partial or broken installations",
                    "logs": "Show recent Millennium / Steam logs",
                }
                for s in subs:
                    d = descs.get(s, s)
                    lines.append(
                        f"complete -c millennium -f -n '__fish_seen_subcommand_from diag' "
                        f"-a '{s}' -d '{d}'"
                    )
                return "\n".join(lines) + "\n"
        if name == "millennium-helpers.nu":
            inner = ", ".join(f'"{s}"' for s in subs)
            return f"  [ {inner} ]\n"
        if name == "millennium-helpers.ps1":
            # Theme PS historically uses remove before update; contract order wins.
            if cmd == "diag":
                # --fix is a flag alias offered alongside subcommands in PS helper.
                inner = ", ".join(f"'{s}'" for s in subs)
                return f"    @({inner}, '--fix')\n"
            inner = ", ".join(f"'{s}'" for s in subs)
            return f"    @({inner})\n"
        fail(f"no renderer for {key} in {path.relative_to(ROOT)}")

    fail(f"unknown façade key {key!r}")


def gofmt_marked_body(prefix: str, key: str, body: str) -> str:
    """Return gofmt-normalized body for a marked Go region."""
    if key == "mcp.dispatch_allowlists":
        # Variable declarations (name = expr), not composite literals.
        wrapper = (
            "package mcp\n\n"
            "var (\n"
            f"{prefix}@@cli-contract:{key}@@\n"
            f"{body}"
            f"{prefix}@@/cli-contract:{key}@@\n"
            ")\n"
        )
    else:
        wrapper = (
            "package mcp\n\n"
            "func _() {\n"
            "\t_ = []any{\n"
            f"{prefix}@@cli-contract:{key}@@\n"
            f"{body}"
            f"{prefix}@@/cli-contract:{key}@@\n"
            "\t}\n"
            "}\n"
        )
    proc = subprocess.run(
        ["gofmt"],
        input=wrapper,
        text=True,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        fail(f"gofmt failed for {key}: {proc.stderr.strip()}")
    pat = marker_re(key)
    m = pat.search(proc.stdout)
    if not m:
        fail(f"gofmt output missing markers for {key}")
    return m.group("body")


def sync_file(path: Path, contract: dict, *, write: bool) -> list[str]:
    """Return list of dirty keys; optionally write updates."""
    text = path.read_text(encoding="utf-8")
    keys = sorted(set(re.findall(r"@@cli-contract:([^@]+)@@", text)))
    # Only start markers (not end markers which use @@/cli-contract:)
    keys = [k for k in keys if not k.startswith("/")]
    dirty: list[str] = []
    new_text = text
    for key in keys:
        pat = marker_re(key)
        matches = list(pat.finditer(new_text))
        if not matches:
            fail(f"{path.relative_to(ROOT)}: malformed markers for {key}")
        raw_body = render_key(contract, key, path)
        key_dirty = False

        def _repl(m: re.Match[str], raw: str = raw_body, k: str = key) -> str:
            nonlocal key_dirty
            prefix = m.group("prefix")
            body = raw
            if path.suffix == ".go":
                body = gofmt_marked_body(prefix, k, raw)
            replacement = (
                f"{prefix}@@cli-contract:{k}@@\n{body}{prefix}@@/cli-contract:{k}@@"
            )
            if m.group(0) != replacement:
                key_dirty = True
            return replacement

        new_text = pat.sub(_repl, new_text)
        if key_dirty:
            dirty.append(key)
    if dirty and write:
        path.write_text(new_text, encoding="utf-8")
    return dirty


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if any marked region differs from the contract",
    )
    args = parser.parse_args()
    contract = load_contract()
    any_dirty = False
    for path in TARGETS:
        if not path.is_file():
            fail(f"missing {path.relative_to(ROOT)}")
        dirty = sync_file(path, contract, write=not args.check)
        if dirty:
            any_dirty = True
            rel = path.relative_to(ROOT)
            if args.check:
                print(
                    f"error: {rel} out of sync with cli-contract ({', '.join(dirty)})",
                    file=sys.stderr,
                )
            else:
                print(f"synced {rel}: {', '.join(dirty)}")
    if args.check and any_dirty:
        print("error: run: make sync-cli-facade", file=sys.stderr)
        raise SystemExit(1)
    if args.check:
        print("cli-facade: OK")
    elif not any_dirty:
        print("cli-facade: already synced")


if __name__ == "__main__":
    main()
