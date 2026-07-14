package mcp

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"

	"github.com/bolens/millenium-helpers/internal/version"
)

// ServeStdio runs the line-delimited JSON-RPC MCP loop.
func ServeStdio(in io.Reader, out io.Writer) error {
	logf("Millennium Helpers MCP server started.")
	sc := bufio.NewScanner(in)
	// MCP tool payloads can be large; raise scanner limit.
	buf := make([]byte, 0, 64*1024)
	sc.Buffer(buf, 10*1024*1024)

	for sc.Scan() {
		line := sc.Text()
		if line == "" {
			continue
		}
		var req map[string]any
		if err := json.Unmarshal([]byte(line), &req); err != nil {
			logf("Error handling request: %v", err)
			continue
		}
		method, _ := req["method"].(string)
		msgID := req["id"]

		switch method {
		case "initialize":
			resp := map[string]any{
				"jsonrpc": "2.0",
				"id":      msgID,
				"result": map[string]any{
					"protocolVersion": "2024-11-05",
					"capabilities":    map[string]any{"tools": map[string]any{}},
					"serverInfo": map[string]any{
						"name":    "millennium-helpers-mcp",
						"version": version.Resolve(),
					},
				},
			}
			if err := writeJSONLine(out, resp); err != nil {
				return err
			}
		case "initialized":
			// notification — no response
		case "tools/list":
			resp := map[string]any{
				"jsonrpc": "2.0",
				"id":      msgID,
				"result":  map[string]any{"tools": ToolsList()},
			}
			if err := writeJSONLine(out, resp); err != nil {
				return err
			}
		case "tools/call":
			params, _ := req["params"].(map[string]any)
			toolName, _ := params["name"].(string)
			arguments, _ := params["arguments"].(map[string]any)
			result := HandleToolCall(toolName, arguments)
			resp := map[string]any{
				"jsonrpc": "2.0",
				"id":      msgID,
				"result":  result,
			}
			if err := writeJSONLine(out, resp); err != nil {
				return err
			}
		default:
			if msgID != nil {
				resp := map[string]any{
					"jsonrpc": "2.0",
					"id":      msgID,
					"error": map[string]any{
						"code":    -32601,
						"message": fmt.Sprintf("Method not found: %s", method),
					},
				}
				if err := writeJSONLine(out, resp); err != nil {
					return err
				}
			}
		}
	}
	return sc.Err()
}
