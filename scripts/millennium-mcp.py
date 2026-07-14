#!/usr/bin/env python3
"""
Model Context Protocol (MCP) server for Millennium Helpers.
Allows AI coding assistants to run diagnostics, manage themes, configure schedules, and apply repairs directly.
"""

import sys
import json
import subprocess
import shutil
import os
import argparse
import base64
from typing import Optional, TypedDict

# Hard upper bound on how long any single underlying millennium-* command is
# allowed to run. The server processes one JSON-RPC request at a time on a
# single thread, so a hung child process (e.g. a stalled network download)
# would otherwise freeze the entire MCP server for every subsequent tool
# call from the AI client with no way to recover short of killing it.
DEFAULT_TIMEOUT_SECONDS = 300
LONG_TIMEOUT_SECONDS = 600

# Server-side allow-lists mirroring the "enum" values declared in
# get_tools_list(). The declared schema is documentation only as far as an
# MCP client is concerned -- nothing stops a client (or a prompt-injected/
# hallucinating model) from sending an arbitrary string for "action" or
# "channel". Without validating here, that string is passed straight
# through to the underlying shell script, which can expose internal-only
# subcommands (e.g. millennium-schedule's "pre-update"/"post-update", which
# close/relaunch Steam outside of the normal enable/disable flow).
VALID_THEME_ACTIONS = {"list", "install", "remove", "update"}
VALID_SCHEDULE_ACTIONS = {"enable", "disable", "status"}
VALID_CHANNELS = {"stable", "beta", "main"}


class DiagArgs(TypedDict, total=False):
    doctor: bool


class ThemeArgs(TypedDict, total=False):
    action: str
    theme: str
    all: bool


class UpgradeArgs(TypedDict, total=False):
    channel: str
    force: bool
    rollback: str


class ScheduleArgs(TypedDict, total=False):
    action: str
    channel: str
    cron: bool
    system: bool
    user: bool


# Logs go to stderr so they don't corrupt the JSON-RPC stdin/stdout transport
def log(msg):
    sys.stderr.write(f"[MCP LOG] {msg}\n")
    sys.stderr.flush()


def get_tools_list():
    return [
        {
            "name": "millennium_diag",
            "description": "Run diagnostics to check the health of the Millennium client, themes, update timers, and configurations. Can optionally run in doctor mode to apply auto-repairs.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "doctor": {
                        "type": "boolean",
                        "description": "Set to true to run auto-repairs. Note: running doctor requires root/sudo privileges.",
                    }
                },
            },
        },
        {
            "name": "millennium_theme",
            "description": "Manage Millennium skins/themes (install, remove, list, update).",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "action": {
                        "type": "string",
                        "enum": ["list", "install", "remove", "update"],
                        "description": "The action to perform.",
                    },
                    "theme": {
                        "type": "string",
                        "description": "Name or GitHub repository URL of the theme (required for install, remove, or updating a single theme).",
                    },
                    "all": {
                        "type": "boolean",
                        "description": "Update all themes (only applicable if action is 'update').",
                    },
                },
                "required": ["action"],
            },
        },
        {
            "name": "millennium_upgrade",
            "description": "Upgrade, reinstall, or roll back the Millennium client on the stable, beta, or main release channel.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "channel": {
                        "type": "string",
                        "enum": ["stable", "beta", "main"],
                        "description": "The release channel to upgrade to (defaults to stable).",
                    },
                    "force": {
                        "type": "boolean",
                        "description": "Force reinstalling or upgrading the client even if it is already up to date.",
                    },
                    "rollback": {
                        "type": "string",
                        "description": "Rollback option. Set to 'list' to view available backup directories, or specify a backup directory name to roll back to that state.",
                    },
                },
            },
        },
        {
            "name": "millennium_schedule",
            "description": "Configure the background update scheduler (enable systemd daily timer or cron job). On Linux, systemd prefers system units when privileged.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "action": {
                        "type": "string",
                        "enum": ["enable", "disable", "status"],
                        "description": "Scheduler action.",
                    },
                    "channel": {
                        "type": "string",
                        "enum": ["stable", "beta", "main"],
                        "description": "Release channel to target (only for 'enable').",
                    },
                    "cron": {
                        "type": "boolean",
                        "description": "Force using crontab instead of systemd.",
                    },
                    "system": {
                        "type": "boolean",
                        "description": "Linux: force systemd system units (requires root).",
                    },
                    "user": {
                        "type": "boolean",
                        "description": "Linux: force systemd user units.",
                    },
                },
                "required": ["action"],
            },
        },
        {
            "name": "millennium_repair",
            "description": "Force reinstalling or repairing the Millennium client (restores hooks and binaries).",
            "inputSchema": {"type": "object", "properties": {}},
        },
        {
            "name": "millennium_purge",
            "description": "Uninstall and completely purge all Millennium client files, themes, and bootstrap hooks. Destructive: requires confirm=true.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "confirm": {
                        "type": "boolean",
                        "description": "Must be true to actually purge. Refuses otherwise.",
                    },
                    "dry_run": {
                        "type": "boolean",
                        "description": "If true, simulate the purge without deleting anything.",
                    },
                },
                "required": ["confirm"],
            },
        },
    ]


IS_WINDOWS = sys.platform == "win32"


def _env_truthy(name: str) -> bool:
    return os.environ.get(name, "").strip().lower() in ("1", "true", "yes")


def force_longnames() -> bool:
    """Escape hatch: keep MCP on long-name helpers (and elevate-safe sudoers)."""
    return _env_truthy("MILLENNIUM_MCP_LONGNAMES") or _env_truthy("MILLENNIUM_LEGACY")


def find_go_dispatcher():
    """Locate the Go `millennium` binary when MCP should prefer it.

    Phase 5b: prefer `millennium <feature> …` for all tools (including elevate)
    when the dispatcher is present. Sudoers allowlists Go verbs plus long-name
    helpers; `MILLENNIUM_MCP_LONGNAMES=1` forces the long-name path.
    """
    if force_longnames():
        return None

    names = ["millennium.exe", "millennium"] if IS_WINDOWS else ["millennium"]
    # Prefer PATH first so TEST_SUITE_RUN / MOCK_BIN stubs win.
    for name in names:
        found = shutil.which(name)
        if found:
            return found

    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    candidates = []
    for name in names:
        candidates.append(os.path.join(repo_root, "bin", name))
        candidates.append(os.path.join(script_dir, name))
        if IS_WINDOWS:
            candidates.append(os.path.join(script_dir, "windows", name))
    for path in candidates:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path

    if not IS_WINDOWS:
        for path in ("/usr/local/bin/millennium", "/usr/bin/millennium"):
            if os.path.isfile(path) and os.access(path, os.X_OK):
                return path
    return None


def feature_argv(feature: str, *rest: str, elevate: bool = False) -> list[str]:
    """Build argv for a feature command; prefer Go dispatcher when available.

    ``elevate`` is retained for call-site clarity; selection uses the same Go
    preference whether or not the command will be wrapped in sudo/UAC.
    """
    del elevate  # selection is identical for elevate vs non-elevate
    go = find_go_dispatcher()
    if go:
        return [go, feature, *rest]
    return [f"millennium-{feature}", *rest]


def find_executable(cmd):
    if os.path.isabs(cmd) and os.path.isfile(cmd):
        return cmd
    if IS_WINDOWS:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        # Check installed folder layout (same directory)
        ps1_path = os.path.join(script_dir, f"{cmd}.ps1")
        if os.path.exists(ps1_path):
            return ps1_path
        # Check repository layout (windows subdirectory)
        ps1_path = os.path.join(script_dir, "windows", f"{cmd}.ps1")
        if os.path.exists(ps1_path):
            return ps1_path
        # Go dispatcher next to scripts / on PATH
        if cmd in ("millennium", "millennium.exe"):
            exe = os.path.join(script_dir, "millennium.exe")
            if os.path.isfile(exe):
                return exe
            exe = os.path.join(script_dir, "windows", "millennium.exe")
            if os.path.isfile(exe):
                return exe
    else:
        for path in ["/usr/local/bin", "/usr/bin"]:
            full_path = f"{path}/{cmd}"
            if shutil.which(full_path):
                return full_path
    return shutil.which(cmd)


def _run_under_test_suite(args, cmd_args, mock_bin, timeout):
    """Log the production command line, then run MOCK_BIN stub or skip.

    find_executable prefers /usr/bin over $PATH mocks, and sudo -n strips
    TEST_SUITE_RUN / MOCK_BIN, so a real millennium-repair/upgrade would
    close and relaunch the developer's Steam client. CI runners also often
    have no system-installed helpers at all.
    """
    log(f"Executing: {' '.join(cmd_args)}")
    mock_key = os.path.basename(args[0])
    mock_path = os.path.join(mock_bin, mock_key) if mock_bin else ""
    if mock_path and os.path.isfile(mock_path) and os.access(mock_path, os.X_OK):
        res = subprocess.run(
            [mock_path] + args[1:],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
        combined_output = ""
        if res.stdout:
            combined_output += res.stdout
        if res.stderr:
            combined_output += f"\n{res.stderr}"
        return {
            "content": [
                {
                    "type": "text",
                    "text": combined_output.strip()
                    or f"Command finished with exit code {res.returncode}",
                }
            ],
            "isError": res.returncode != 0,
        }
    log("[TEST] Skipping host execution to protect Steam/system state")
    return {
        "content": [{"type": "text", "text": "[TEST] Skipped host execution"}],
        "isError": False,
    }


def run_cmd(args, run_as_root=False, timeout=DEFAULT_TIMEOUT_SECONDS):
    executable = find_executable(args[0])
    test_suite = bool(os.environ.get("TEST_SUITE_RUN"))
    mock_bin = os.environ.get("MOCK_BIN", "")

    if not executable:
        if not test_suite:
            return {
                "isError": True,
                "content": [
                    {
                        "type": "text",
                        "text": f"Error: Command '{args[0]}' not found on system.",
                    }
                ],
            }
        # Still log a production-shaped command line so tests can assert on it.
        cmd_args = list(args)
        if run_as_root:
            cmd_args = (["sudo.exe"] if IS_WINDOWS else ["sudo", "-n"]) + cmd_args
        try:
            return _run_under_test_suite(args, cmd_args, mock_bin, timeout)
        except subprocess.TimeoutExpired:
            log(f"Command timed out after {timeout}s: {' '.join(cmd_args)}")
            return {
                "isError": True,
                "content": [
                    {
                        "type": "text",
                        "text": f"Error: Command '{' '.join(args)}' timed out after {timeout} seconds and was terminated.",
                    }
                ],
            }

    if IS_WINDOWS and executable.endswith(".ps1"):
        cmd_args = [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            executable,
        ] + args[1:]

        if run_as_root:
            if shutil.which("sudo.exe"):
                cmd_args = ["sudo.exe"] + cmd_args
            else:
                # Avoid ArgumentList quote interpolation. Elevate via
                # -EncodedCommand that builds a -File + argument array.
                ps_lines = [
                    "$ErrorActionPreference = 'Stop'",
                    f"$exe = {json.dumps(executable)}",
                    "$argList = @(",
                ]
                for a in args[1:]:
                    ps_lines.append(f"  {json.dumps(a)},")
                ps_lines.append(")")
                ps_lines.append(
                    "Start-Process -FilePath powershell.exe -Verb RunAs -Wait "
                    "-ArgumentList (@('-NoProfile','-ExecutionPolicy','Bypass','-File',$exe) + $argList)"
                )
                script_body = "\n".join(ps_lines) + "\n"
                encoded = base64.b64encode(script_body.encode("utf-16le")).decode(
                    "ascii"
                )
                cmd_args = [
                    "powershell.exe",
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-EncodedCommand",
                    encoded,
                ]
    elif IS_WINDOWS:
        # Go dispatcher (.exe) or other non-PS1 binaries
        cmd_args = [executable] + args[1:]
        if run_as_root:
            if shutil.which("sudo.exe"):
                cmd_args = ["sudo.exe"] + cmd_args
            else:
                ps_lines = [
                    "$ErrorActionPreference = 'Stop'",
                    f"$exe = {json.dumps(executable)}",
                    "$argList = @(",
                ]
                for a in args[1:]:
                    ps_lines.append(f"  {json.dumps(a)},")
                ps_lines.append(")")
                ps_lines.append(
                    "Start-Process -FilePath $exe -Verb RunAs -Wait -ArgumentList $argList"
                )
                script_body = "\n".join(ps_lines) + "\n"
                encoded = base64.b64encode(script_body.encode("utf-16le")).decode(
                    "ascii"
                )
                cmd_args = [
                    "powershell.exe",
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-EncodedCommand",
                    encoded,
                ]
    else:
        cmd_args = [executable] + args[1:]
        if run_as_root:
            cmd_args = ["sudo", "-n"] + cmd_args

    # Always log the production command line (tests assert against this).
    try:
        if test_suite:
            return _run_under_test_suite(args, cmd_args, mock_bin, timeout)

        log(f"Executing: {' '.join(cmd_args)}")
        res = subprocess.run(
            cmd_args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
        combined_output = ""
        if res.stdout:
            combined_output += res.stdout
        if res.stderr:
            combined_output += f"\n{res.stderr}"

        return {
            "content": [
                {
                    "type": "text",
                    "text": combined_output.strip()
                    or f"Command finished with exit code {res.returncode}",
                }
            ],
            "isError": res.returncode != 0,
        }
    except subprocess.TimeoutExpired:
        log(f"Command timed out after {timeout}s: {' '.join(cmd_args)}")
        return {
            "isError": True,
            "content": [
                {
                    "type": "text",
                    "text": f"Error: Command '{' '.join(args)}' timed out after {timeout} seconds and was terminated.",
                }
            ],
        }
    except Exception as e:
        return {
            "content": [{"type": "text", "text": f"Execution error: {e}"}],
            "isError": True,
        }


def handle_tool_call(
    tool_name: str, arguments: DiagArgs | ThemeArgs | UpgradeArgs | ScheduleArgs | dict
) -> dict:
    if tool_name == "millennium_diag":
        doctor = arguments.get("doctor", False)
        if doctor:
            return run_cmd(
                feature_argv("diag", "doctor", elevate=True), run_as_root=True
            )
        return run_cmd(feature_argv("diag", "--json"))

    elif tool_name == "millennium_theme":
        action = arguments.get("action")
        theme = arguments.get("theme")
        all_themes = arguments.get("all", False)

        if theme:
            if ".." in theme:
                return {
                    "isError": True,
                    "content": [
                        {
                            "type": "text",
                            "text": "Error: theme name/URL contains invalid characters.",
                        }
                    ],
                }
            import re

            if not re.match(r"^[a-zA-Z0-9_\-\./:]+$", theme):
                return {
                    "isError": True,
                    "content": [
                        {
                            "type": "text",
                            "text": "Error: theme name/URL contains invalid characters.",
                        }
                    ],
                }

        if action not in VALID_THEME_ACTIONS:
            return {
                "isError": True,
                "content": [
                    {
                        "type": "text",
                        "text": f"Error: invalid action '{action}'. Must be one of: {', '.join(sorted(VALID_THEME_ACTIONS))}.",
                    }
                ],
            }

        rest: list[str] = [action]
        if action == "list":
            rest.append("--json")
        elif action in ["install", "remove"]:
            if not theme:
                return {
                    "isError": True,
                    "content": [
                        {
                            "type": "text",
                            "text": "Error: theme name/URL is required for install/remove actions.",
                        }
                    ],
                }
            rest.append(theme)
        elif action == "update":
            if all_themes:
                rest.append("--all")
            elif theme:
                rest.append(theme)
        return run_cmd(feature_argv("theme", *rest), timeout=LONG_TIMEOUT_SECONDS)

    elif tool_name == "millennium_upgrade":
        channel = arguments.get("channel", "stable")
        force = arguments.get("force", False)
        rollback = arguments.get("rollback")

        if channel not in VALID_CHANNELS:
            return {
                "isError": True,
                "content": [
                    {
                        "type": "text",
                        "text": f"Error: invalid channel '{channel}'. Must be one of: {', '.join(sorted(VALID_CHANNELS))}.",
                    }
                ],
            }

        rest: list[str] = ["--channel", channel]
        if force:
            rest.append("--force")
        if rollback:
            import re

            if rollback != "list" and not re.match(r"^[a-zA-Z0-9_\-\.]+$", rollback):
                return {
                    "isError": True,
                    "content": [
                        {
                            "type": "text",
                            "text": "Error: invalid rollback target name format.",
                        }
                    ],
                }
            rest += ["--rollback", rollback]

        return run_cmd(
            feature_argv("upgrade", *rest, elevate=True),
            run_as_root=True,
            timeout=LONG_TIMEOUT_SECONDS,
        )

    elif tool_name == "millennium_schedule":
        action = arguments.get("action")
        channel = arguments.get("channel")
        cron = arguments.get("cron", False)
        system = arguments.get("system", False)
        user = arguments.get("user", False)

        if action not in VALID_SCHEDULE_ACTIONS:
            return {
                "isError": True,
                "content": [
                    {
                        "type": "text",
                        "text": f"Error: invalid action '{action}'. Must be one of: {', '.join(sorted(VALID_SCHEDULE_ACTIONS))}.",
                    }
                ],
            }
        if channel is not None and channel not in VALID_CHANNELS:
            return {
                "isError": True,
                "content": [
                    {
                        "type": "text",
                        "text": f"Error: invalid channel '{channel}'. Must be one of: {', '.join(sorted(VALID_CHANNELS))}.",
                    }
                ],
            }
        if system and user:
            return {
                "isError": True,
                "content": [
                    {
                        "type": "text",
                        "text": "Error: cannot combine system=true and user=true.",
                    }
                ],
            }

        rest = [action]
        if action == "enable" and channel:
            rest.append(channel)
        if cron:
            rest.append("--cron")
        if system:
            rest.append("--system")
        if user:
            rest.append("--user")
        return run_cmd(feature_argv("schedule", *rest))

    elif tool_name == "millennium_repair":
        return run_cmd(
            feature_argv("repair", elevate=True),
            run_as_root=True,
            timeout=LONG_TIMEOUT_SECONDS,
        )

    elif tool_name == "millennium_purge":
        confirm = bool(arguments.get("confirm", False))
        dry_run = bool(arguments.get("dry_run", False))
        if not confirm and not dry_run:
            return {
                "isError": True,
                "content": [
                    {
                        "type": "text",
                        "text": "Error: millennium_purge requires confirm=true (or dry_run=true to simulate). This permanently removes Millennium.",
                    }
                ],
            }
        rest: list[str] = []
        if dry_run:
            rest.append("-DryRun" if IS_WINDOWS else "--dry-run")
        else:
            rest.append("-Yes" if IS_WINDOWS else "--yes")
        return run_cmd(
            feature_argv("purge", *rest, elevate=True),
            run_as_root=True,
            timeout=LONG_TIMEOUT_SECONDS,
        )

    else:
        return {
            "content": [{"type": "text", "text": f"Unknown tool: {tool_name}"}],
            "isError": True,
        }


def get_helpers_version():
    candidates = []
    script_dir = os.path.dirname(os.path.abspath(__file__))
    candidates.append(os.path.join(script_dir, "..", "VERSION"))
    candidates.append(os.path.join(script_dir, "VERSION"))
    candidates.append("/usr/local/lib/millennium-helpers/VERSION")
    candidates.append("/usr/lib/millennium-helpers/VERSION")
    for path in candidates:
        if os.path.isfile(path):
            try:
                with open(path, encoding="utf-8") as f:
                    ver = f.read().strip()
                if ver:
                    return ver
            except OSError:
                pass
    return "unknown"


def register_mcp():
    home = os.path.expanduser("~")

    # Define configurations
    if sys.platform == "win32":
        claude_path = os.path.join(
            os.environ.get("APPDATA", ""), "Claude", "claude_desktop_config.json"
        )
    else:
        claude_path = os.path.join(
            home, ".config", "Claude", "claude_desktop_config.json"
        )

    windsurf_path = os.path.join(home, ".codeium", "windsurf", "mcp_config.json")
    cursor_path = os.path.join(home, ".cursor", "mcp.json")

    configs = [
        ("Claude Desktop", claude_path, "mcpServers"),
        ("Windsurf", windsurf_path, "mcpServers"),
        ("Cursor", cursor_path, "mcpServers"),
    ]

    # The server name and command
    server_name = "millennium-helpers"
    server_config = {"command": "millennium-mcp"}

    registered_any = False

    for label, path, key in configs:
        # Ensure the parent directory exists
        dir_path = os.path.dirname(path)
        if not os.path.exists(dir_path):
            continue

        print(f"Registering Millennium Helpers MCP server in {label}...")

        data = {}
        if os.path.exists(path):
            try:
                with open(path, "r") as f:
                    data = json.load(f)
            except Exception as e:
                print(
                    f"  Warning: failed to read existing config at {path}: {e}. Creating new."
                )

        if key not in data:
            data[key] = {}

        # Check if already registered
        if (
            server_name in data[key]
            and data[key][server_name].get("command") == "millennium-mcp"
        ):
            print(f"  Already registered in {label}.")
            registered_any = True
            continue

        data[key][server_name] = server_config

        try:
            with open(path, "w") as f:
                json.dump(data, f, indent=2)
            print(f"  Successfully registered in {label} config: {path}")
            registered_any = True
        except Exception as e:
            print(f"  Error: failed to write config to {path}: {e}")

    snippet = {"mcpServers": {server_name: server_config}}
    print("\nManual config snippet (any MCP host):")
    print(json.dumps(snippet, indent=2))

    if not registered_any:
        print(
            "\nNo active config directories found (Claude Desktop, Windsurf, or Cursor)."
        )
        print("Paste the snippet above into your MCP client's config file.")
        sys.exit(1)
    else:
        print("\nRegistration check completed successfully.")
        print("Restart Cursor / Claude Desktop / Windsurf so the MCP server appears.")
        print("See docs/mcp.md for tool details and troubleshooting.")
        sys.exit(0)


def prefer_go_mcp_server() -> Optional[str]:
    """Return the Go dispatcher path when this process should re-exec into it.

    Phase 5c.1: production stdio/version/help prefer ``millennium mcp``.
    Skip when forced to Python, under TEST_SUITE_RUN (mocks shadow ``millennium``),
    or for ``--register`` (still Python-only).
    """
    if _env_truthy("MILLENNIUM_MCP_PYTHON") or _env_truthy("MILLENNIUM_LEGACY"):
        return None
    if _env_truthy("TEST_SUITE_RUN"):
        return None
    return find_go_dispatcher()


def maybe_exec_go_mcp(extra_argv: list[str]) -> None:
    go = prefer_go_mcp_server()
    if not go:
        return
    os.execv(go, [go, "mcp", *extra_argv])


def main():
    parser = argparse.ArgumentParser(
        description="Model Context Protocol (MCP) server for Millennium Helpers."
    )
    parser.add_argument(
        "--register",
        "-r",
        action="store_true",
        help="Register the MCP server with Claude Desktop, Windsurf, and Cursor.",
    )
    parser.add_argument(
        "-V", "--version", action="store_true", help="Show version information."
    )
    args = parser.parse_args()

    if args.register:
        register_mcp()
        return

    # Prefer native Go MCP for stdio / --version / --help (argparse already ate flags).
    go_argv: list[str] = []
    if args.version:
        go_argv.append("--version")
    maybe_exec_go_mcp(go_argv)

    if args.version:
        print(f"millennium-mcp {get_helpers_version()}")
        return

    log("Millennium Helpers MCP server started.")
    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break
            req = json.loads(line)
            method = req.get("method")
            msg_id = req.get("id")

            if method == "initialize":
                resp = {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": {
                        "protocolVersion": "2024-11-05",
                        "capabilities": {"tools": {}},
                        "serverInfo": {
                            "name": "millennium-helpers-mcp",
                            "version": get_helpers_version(),
                        },
                    },
                }
                sys.stdout.write(json.dumps(resp) + "\n")
                sys.stdout.flush()
            elif method == "initialized":
                pass
            elif method == "tools/list":
                resp = {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": {"tools": get_tools_list()},
                }
                sys.stdout.write(json.dumps(resp) + "\n")
                sys.stdout.flush()
            elif method == "tools/call":
                params = req.get("params", {})
                tool_name = params.get("name")
                arguments = params.get("arguments", {})
                result = handle_tool_call(tool_name, arguments)
                resp = {"jsonrpc": "2.0", "id": msg_id, "result": result}
                sys.stdout.write(json.dumps(resp) + "\n")
                sys.stdout.flush()
            else:
                if msg_id is not None:
                    resp = {
                        "jsonrpc": "2.0",
                        "id": msg_id,
                        "error": {
                            "code": -32601,
                            "message": f"Method not found: {method}",
                        },
                    }
                    sys.stdout.write(json.dumps(resp) + "\n")
                    sys.stdout.flush()
        except Exception as e:
            log(f"Error handling request: {e}")


if __name__ == "__main__":
    main()
