package diag

import (
	"fmt"
	"io"
	"os"
	"runtime"
	"strings"
	"time"

	"github.com/bolens/millenium-helpers/internal/schedule"
)

// Test seams for FollowLogs (avoid hanging the suite).
var (
	followPollInterval = 200 * time.Millisecond
	followMaxCycles    = 0 // 0 = until process exit / Ctrl+C
)

// logFilterParts returns lowercase substrings for Millennium-related lines.
func logFilterParts() []string {
	parts := []string{"millennium", "bootstrap", "update-check", "plugin_loader", "steamwebhelper"}
	if runtime.GOOS == "windows" {
		parts = append(parts, "wsock32")
	} else {
		parts = append(parts, "pressure-vessel")
	}
	return parts
}

func lineMatchesFilter(line string, parts []string) bool {
	low := strings.ToLower(line)
	for _, p := range parts {
		if strings.Contains(low, p) {
			return true
		}
	}
	return false
}

// FollowLogs prints updater tail once, then filter-tails the newest Steam log.
func FollowLogs() int {
	state := schedule.LogPath()
	if st, err := os.Stat(state); err == nil && st.Mode().IsRegular() {
		fmt.Println("=== Millennium Background Auto-Updater Logs ===")
		_ = printTail(state, 50)
		fmt.Println()
	}
	fmt.Println("=== Millennium & Steam WebHelper Logs ===")
	logFile := newestSteamLog()
	if logFile == "" {
		fmt.Fprintln(os.Stderr, "Error: No Steam logs found on this system.")
		return 1
	}
	fmt.Printf("Reading log file: %s\n\n", logFile)
	fmt.Println("Tailing log file (Ctrl+C to exit)...")
	return followFiltered(logFile, logFilterParts(), 100)
}

func followFiltered(path string, parts []string, initialTail int) int {
	lines, err := tailLines(path, initialTail)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	for _, line := range lines {
		if lineMatchesFilter(line, parts) {
			fmt.Println(line)
		}
	}

	f, err := os.Open(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}
	defer f.Close()
	offset, err := f.Seek(0, io.SeekEnd)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return 1
	}

	var partial string
	cycles := 0
	for {
		if followMaxCycles > 0 && cycles >= followMaxCycles {
			return 0
		}
		cycles++

		st, err := os.Stat(path)
		if err != nil {
			time.Sleep(followPollInterval)
			continue
		}
		// Handle truncate / rotate (inode change): reopen if needed.
		if st.Size() < offset {
			_ = f.Close()
			f, err = os.Open(path)
			if err != nil {
				time.Sleep(followPollInterval)
				continue
			}
			offset = 0
			partial = ""
		}
		if st.Size() == offset {
			time.Sleep(followPollInterval)
			continue
		}
		if _, err := f.Seek(offset, io.SeekStart); err != nil {
			time.Sleep(followPollInterval)
			continue
		}
		buf := make([]byte, st.Size()-offset)
		n, err := io.ReadFull(f, buf)
		if err != nil && err != io.ErrUnexpectedEOF && err != io.EOF {
			time.Sleep(followPollInterval)
			continue
		}
		if n <= 0 {
			time.Sleep(followPollInterval)
			continue
		}
		offset += int64(n)
		data := partial + string(buf[:n])
		chunks := strings.Split(strings.ReplaceAll(data, "\r\n", "\n"), "\n")
		if strings.HasSuffix(data, "\n") || strings.HasSuffix(data, "\r\n") {
			partial = ""
		} else if len(chunks) > 0 {
			partial = chunks[len(chunks)-1]
			chunks = chunks[:len(chunks)-1]
		}
		for _, line := range chunks {
			if lineMatchesFilter(line, parts) {
				fmt.Println(line)
			}
		}
	}
}
