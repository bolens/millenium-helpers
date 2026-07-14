package mcp

import (
	"fmt"
	"os"
	"strings"

	"github.com/bolens/millenium-helpers/internal/version"
)

// Options are parsed from `millennium mcp` argv.
type Options struct {
	Register bool
	Version  bool
	Help     bool
}

// ParseArgs parses mcp flags. Returns help text via Help.
func ParseArgs(args []string) (Options, error) {
	var opts Options
	for _, a := range args {
		switch a {
		case "-r", "--register":
			opts.Register = true
		case "-V", "--version":
			opts.Version = true
		case "-h", "--help":
			opts.Help = true
		default:
			if strings.HasPrefix(a, "-") {
				return opts, fmt.Errorf("unrecognized arguments: %s", a)
			}
			return opts, fmt.Errorf("unrecognized arguments: %s", a)
		}
	}
	return opts, nil
}

// RunCLI handles version/help or serves stdio MCP. Register is handled by the caller (Python).
func RunCLI(opts Options) int {
	if opts.Help {
		fmt.Print(`Usage: millennium mcp [OPTIONS]

Model Context Protocol (MCP) server for Millennium Helpers.

Options:
  -r, --register   Register with Claude Desktop / Windsurf / Cursor
  -V, --version    Show version information
  -h, --help       Show this help message
`)
		return 0
	}
	if opts.Version {
		fmt.Printf("millennium-mcp %s\n", version.Resolve())
		return 0
	}
	if opts.Register {
		return RunRegister()
	}
	if err := ServeStdio(os.Stdin, os.Stdout); err != nil {
		logf("Error: %v", err)
		return 1
	}
	return 0
}
