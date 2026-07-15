#!/usr/bin/env python3
"""Sync marked completion regions from spec/cli-contract.yaml.

Marked blocks use:
  # @@cli-contract:<key>@@
  ... generated ...
  # @@/cli-contract:<key>@@

Keys:
  dispatcher.commands
  commands.<name>.subcommands
  commands.<name>.flags
  commands.install_uninstall.flags   # bash shared install|uninstall completer
  channels

Usage:
  python3 scripts/ci/sync-cli-facade.py          # write
  python3 scripts/ci/sync-cli-facade.py --check  # CI: fail if dirty
Prefer: make sync-cli-facade / make check-cli-contract
"""

from __future__ import annotations

import argparse
import re
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
]


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
        body = render_key(contract, key, path)
        key_dirty = False

        def _repl(m: re.Match[str], b: str = body, k: str = key) -> str:
            nonlocal key_dirty
            prefix = m.group("prefix")
            replacement = (
                f"{prefix}@@cli-contract:{k}@@\n{b}{prefix}@@/cli-contract:{k}@@"
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
