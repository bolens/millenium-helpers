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
VALID_CHANNELS = {"stable", "beta"}

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
                        "description": "Set to true to run auto-repairs. Note: running doctor requires root/sudo privileges."
                    }
                }
            }
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
                        "description": "The action to perform."
                    },
                    "theme": {
                        "type": "string",
                        "description": "Name or GitHub repository URL of the theme (required for install, remove, or updating a single theme)."
                    },
                    "all": {
                        "type": "boolean",
                        "description": "Update all themes (only applicable if action is 'update')."
                    }
                },
                "required": ["action"]
            }
        },
        {
            "name": "millennium_upgrade",
            "description": "Upgrade the Millennium client to the latest version on the stable or beta release channel.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "channel": {
                        "type": "string",
                        "enum": ["stable", "beta"],
                        "description": "The release channel to upgrade to (defaults to stable)."
                    }
                }
            }
        },
        {
            "name": "millennium_schedule",
            "description": "Configure the background update scheduler (enable systemd daily timer or cron job).",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "action": {
                        "type": "string",
                        "enum": ["enable", "disable", "status"],
                        "description": "Scheduler action."
                    },
                    "channel": {
                        "type": "string",
                        "enum": ["stable", "beta"],
                        "description": "Release channel to target (only for 'enable')."
                    },
                    "cron": {
                        "type": "boolean",
                        "description": "Force using crontab instead of systemd."
                    }
                },
                "required": ["action"]
            }
        },
        {
            "name": "millennium_repair",
            "description": "Force reinstalling or repairing the Millennium client (restores hooks and binaries).",
            "inputSchema": {
                "type": "object",
                "properties": {}
            }
        },
        {
            "name": "millennium_purge",
            "description": "Uninstall and completely purge all Millennium client files, themes, and bootstrap hooks.",
            "inputSchema": {
                "type": "object",
                "properties": {}
            }
        }
    ]

IS_WINDOWS = sys.platform == "win32"

def find_executable(cmd):
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
    else:
        for path in ["/usr/local/bin", "/usr/bin"]:
            full_path = f"{path}/{cmd}"
            if shutil.which(full_path):
                return full_path
    return shutil.which(cmd)

def run_cmd(args, run_as_root=False, timeout=DEFAULT_TIMEOUT_SECONDS):
    executable = find_executable(args[0])
    if not executable:
        return {"isError": True, "content": [{"type": "text", "text": f"Error: Command '{args[0]}' not found on system."}]}
    
    if IS_WINDOWS and executable.endswith(".ps1"):
        cmd_args = [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", executable
        ] + args[1:]
        
        if run_as_root:
            if shutil.which("sudo.exe"):
                cmd_args = ["sudo.exe"] + cmd_args
            else:
                # Run elevated via shell Start-Process
                ps_args = f'-NoProfile -ExecutionPolicy Bypass -File "{executable}" ' + ' '.join(f'"{a}"' for a in args[1:])
                cmd_args = [
                    "powershell.exe",
                    "-Command",
                    f"Start-Process powershell -Verb RunAs -Wait -ArgumentList '{ps_args}'"
                ]
    else:
        cmd_args = [executable] + args[1:]
        if run_as_root:
            cmd_args = ["sudo", "-n"] + cmd_args
        
    try:
        log(f"Executing: {' '.join(cmd_args)}")
        res = subprocess.run(cmd_args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=timeout)
        combined_output = ""
        if res.stdout:
            combined_output += res.stdout
        if res.stderr:
            combined_output += f"\n{res.stderr}"
            
        return {
            "content": [
                {
                    "type": "text",
                    "text": combined_output.strip() or f"Command finished with exit code {res.returncode}"
                }
            ],
            "isError": res.returncode != 0
        }
    except subprocess.TimeoutExpired:
        log(f"Command timed out after {timeout}s: {' '.join(cmd_args)}")
        return {
            "isError": True,
            "content": [{"type": "text", "text": f"Error: Command '{' '.join(args)}' timed out after {timeout} seconds and was terminated."}]
        }
    except Exception as e:
        return {
            "content": [{"type": "text", "text": f"Execution error: {e}"}],
            "isError": True
        }

def handle_tool_call(tool_name, arguments):
    if tool_name == "millennium_diag":
        doctor = arguments.get("doctor", False)
        args = ["millennium-diag"]
        if doctor:
            args.append("doctor")
        else:
            args.append("--json")
        return run_cmd(args, run_as_root=doctor)
        
    elif tool_name == "millennium_theme":
        action = arguments.get("action")
        theme = arguments.get("theme")
        all_themes = arguments.get("all", False)

        if action not in VALID_THEME_ACTIONS:
            return {"isError": True, "content": [{"type": "text", "text": f"Error: invalid action '{action}'. Must be one of: {', '.join(sorted(VALID_THEME_ACTIONS))}."}]}

        args = ["millennium-theme", action]
        if action == "list":
            args.append("--json")
        elif action in ["install", "remove"]:
            if not theme:
                return {"isError": True, "content": [{"type": "text", "text": "Error: theme name/URL is required for install/remove actions."}]}
            args.append(theme)
        elif action == "update":
            if all_themes:
                args.append("--all")
            elif theme:
                args.append(theme)
        return run_cmd(args, timeout=LONG_TIMEOUT_SECONDS)
        
    elif tool_name == "millennium_upgrade":
        channel = arguments.get("channel", "stable")
        if channel not in VALID_CHANNELS:
            return {"isError": True, "content": [{"type": "text", "text": f"Error: invalid channel '{channel}'. Must be one of: {', '.join(sorted(VALID_CHANNELS))}."}]}
        args = ["millennium-upgrade", "--channel", channel]
        return run_cmd(args, run_as_root=True, timeout=LONG_TIMEOUT_SECONDS)
        
    elif tool_name == "millennium_schedule":
        action = arguments.get("action")
        channel = arguments.get("channel")
        cron = arguments.get("cron", False)

        if action not in VALID_SCHEDULE_ACTIONS:
            return {"isError": True, "content": [{"type": "text", "text": f"Error: invalid action '{action}'. Must be one of: {', '.join(sorted(VALID_SCHEDULE_ACTIONS))}."}]}
        if channel is not None and channel not in VALID_CHANNELS:
            return {"isError": True, "content": [{"type": "text", "text": f"Error: invalid channel '{channel}'. Must be one of: {', '.join(sorted(VALID_CHANNELS))}."}]}

        args = ["millennium-schedule", action]
        if action == "enable" and channel:
            args.append(channel)
        if cron:
            args.append("--cron")
        return run_cmd(args)
        
    elif tool_name == "millennium_repair":
        return run_cmd(["millennium-repair"], run_as_root=True, timeout=LONG_TIMEOUT_SECONDS)
        
    elif tool_name == "millennium_purge":
        return run_cmd(["millennium-purge"], run_as_root=True, timeout=LONG_TIMEOUT_SECONDS)
        
    else:
        return {
            "content": [{"type": "text", "text": f"Unknown tool: {tool_name}"}],
            "isError": True
        }

def register_mcp():
    home = os.path.expanduser("~")

    # Define configurations
    if sys.platform == "win32":
        claude_path = os.path.join(os.environ.get("APPDATA", ""), "Claude", "claude_desktop_config.json")
    else:
        claude_path = os.path.join(home, ".config", "Claude", "claude_desktop_config.json")
        
    windsurf_path = os.path.join(home, ".codeium", "windsurf", "mcp_config.json")

    configs = [
        ("Claude Desktop", claude_path, "mcpServers"),
        ("Windsurf", windsurf_path, "mcpServers")
    ]

    # The server name and command
    server_name = "millennium-helpers"
    server_config = {
        "command": "millennium-mcp"
    }

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
                print(f"  Warning: failed to read existing config at {path}: {e}. Creating new.")

        if key not in data:
            data[key] = {}

        # Check if already registered
        if server_name in data[key] and data[key][server_name].get("command") == "millennium-mcp":
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

    if not registered_any:
        print("No active config directories found (Claude Desktop or Windsurf).")
        print("Please configure manually as described in the README.")
        sys.exit(1)
    else:
        print("Registration check completed successfully.")
        sys.exit(0)

def main():
    parser = argparse.ArgumentParser(description="Model Context Protocol (MCP) server for Millennium Helpers.")
    parser.add_argument("--register", "-r", action="store_true", help="Register the MCP server with Claude Desktop and Windsurf.")
    args = parser.parse_args()

    if args.register:
        register_mcp()
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
                        "capabilities": {
                            "tools": {}
                        },
                        "serverInfo": {
                            "name": "millennium-helpers-mcp",
                            "version": "1.0.0"
                        }
                    }
                }
                sys.stdout.write(json.dumps(resp) + "\n")
                sys.stdout.flush()
            elif method == "initialized":
                pass
            elif method == "tools/list":
                resp = {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": {
                        "tools": get_tools_list()
                    }
                }
                sys.stdout.write(json.dumps(resp) + "\n")
                sys.stdout.flush()
            elif method == "tools/call":
                params = req.get("params", {})
                tool_name = params.get("name")
                arguments = params.get("arguments", {})
                result = handle_tool_call(tool_name, arguments)
                resp = {
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": result
                }
                sys.stdout.write(json.dumps(resp) + "\n")
                sys.stdout.flush()
            else:
                if msg_id is not None:
                    resp = {
                        "jsonrpc": "2.0",
                        "id": msg_id,
                        "error": {
                            "code": -32601,
                            "message": f"Method not found: {method}"
                        }
                    }
                    sys.stdout.write(json.dumps(resp) + "\n")
                    sys.stdout.flush()
        except Exception as e:
            log(f"Error handling request: {e}")

if __name__ == "__main__":
    main()

