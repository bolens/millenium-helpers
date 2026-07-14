package mcp

import (
	"fmt"
	"os"
)

func logf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "[MCP LOG] "+format+"\n", args...)
}
