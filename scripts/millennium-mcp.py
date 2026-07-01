#!/usr/bin/env python3
"""
Model Context Protocol (MCP) server for Millennium Helpers.
Allows AI coding assistants to run diagnostics, manage themes, configure schedules, and apply repairs directly.
"""
import sys
import json
import subprocess
import shutil

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

def find_executable(cmd):
    for path in ["/usr/local/bin", "/usr/bin"]:
        full_path = f"{path}/{cmd}"
        if shutil.which(full_path):
            return full_path
    return shutil.which(cmd)

def run_cmd(args, run_as_root=False):
    executable = find_executable(args[0])
    if not executable:
        return {"isError": True, "content": [{"type": "text", "text": f"Error: Command '{args[0]}' not found on system."}]}
    
    cmd_args = [executable] + args[1:]
    if run_as_root:
        cmd_args = ["sudo", "-n"] + cmd_args
        
    try:
        log(f"Executing: {' '.join(cmd_args)}")
        res = subprocess.run(cmd_args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
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
        return run_cmd(args, run_as_root=doctor)
        
    elif tool_name == "millennium_theme":
        action = arguments.get("action")
        theme = arguments.get("theme")
        all_themes = arguments.get("all", False)
        
        args = ["millennium-theme", action]
        if action in ["install", "remove"]:
            if not theme:
                return {"isError": True, "content": [{"type": "text", "text": "Error: theme name/URL is required for install/remove actions."}]}
            args.append(theme)
        elif action == "update":
            if all_themes:
                args.append("--all")
            elif theme:
                args.append(theme)
        return run_cmd(args)
        
    elif tool_name == "millennium_upgrade":
        channel = arguments.get("channel", "stable")
        if channel == "beta":
            args = ["millennium-upgrade-beta"]
        else:
            args = ["millennium-upgrade-stable"]
        return run_cmd(args, run_as_root=True)
        
    elif tool_name == "millennium_schedule":
        action = arguments.get("action")
        channel = arguments.get("channel")
        cron = arguments.get("cron", False)
        
        args = ["millennium-schedule", action]
        if action == "enable" and channel:
            args.append(channel)
        if cron:
            args.append("--cron")
        return run_cmd(args)
        
    elif tool_name == "millennium_repair":
        return run_cmd(["millennium-repair"])
        
    elif tool_name == "millennium_purge":
        return run_cmd(["millennium-purge"], run_as_root=True)
        
    else:
        return {
            "content": [{"type": "text", "text": f"Unknown tool: {tool_name}"}],
            "isError": True
        }

def main():
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
