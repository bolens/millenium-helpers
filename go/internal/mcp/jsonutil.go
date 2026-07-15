package mcp

import (
	"encoding/json"
	"io"
)

// writeJSONLine encodes v with spaces after ':' and ',' (Python json.dumps
// defaults) so behavioral tests that substring-match "id": 1 keep working.
func writeJSONLine(w io.Writer, v any) error {
	b, err := json.Marshal(v)
	if err != nil {
		return err
	}
	b = pythonStyleJSON(b)
	_, err = w.Write(append(b, '\n'))
	return err
}

func pythonStyleJSON(b []byte) []byte {
	out := make([]byte, 0, len(b)+32)
	inStr := false
	esc := false
	for i := 0; i < len(b); i++ {
		c := b[i]
		if inStr {
			out = append(out, c)
			if esc {
				esc = false
			} else if c == '\\' {
				esc = true
			} else if c == '"' {
				inStr = false
			}
			continue
		}
		switch c {
		case '"':
			inStr = true
			out = append(out, c)
		case ':':
			out = append(out, ':', ' ')
		case ',':
			out = append(out, ',', ' ')
		default:
			out = append(out, c)
		}
	}
	return out
}
