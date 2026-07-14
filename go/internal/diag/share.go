package diag

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"os/user"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/bolens/millenium-helpers/internal/config"
	"github.com/bolens/millenium-helpers/internal/schedule"
)

var (
	ghpPATRE      = regexp.MustCompile(`ghp_[A-Za-z0-9_]+`)
	githubFineRE  = regexp.MustCompile(`github_pat_[A-Za-z0-9_]+`)
	pasteEndpoint = "https://paste.rs"
	httpDo        = defaultHTTPDo
)

func defaultHTTPDo(req *http.Request) (*http.Response, error) {
	client := &http.Client{Timeout: 45 * time.Second}
	return client.Do(req)
}

// RedactReport sanitizes user identity and tokens from a report body.
func RedactReport(body string) string {
	home, _ := os.UserHomeDir()
	uname := os.Getenv("USER")
	if uname == "" {
		uname = os.Getenv("USERNAME")
	}
	if uname == "" {
		if u, err := user.Current(); err == nil {
			uname = u.Username
		}
	}
	out := body
	if home != "" {
		out = strings.ReplaceAll(out, home, "~")
	}
	if uname != "" && len(uname) >= 2 {
		out = strings.ReplaceAll(out, uname, "user")
	}
	out = ghpPATRE.ReplaceAllString(out, "[REDACTED]")
	out = githubFineRE.ReplaceAllString(out, "[REDACTED]")
	if tok := strings.TrimSpace(os.Getenv("GITHUB_TOKEN")); len(tok) >= 4 {
		out = strings.ReplaceAll(out, tok, "[REDACTED]")
	}
	if data, err := config.Load(); err == nil {
		if tok := config.Get(data, "github_token"); len(tok) >= 4 {
			out = strings.ReplaceAll(out, tok, "[REDACTED]")
		}
	}
	return out
}

// UploadPasteRS POSTs text/plain body and returns the paste URL.
func UploadPasteRS(body string) (string, error) {
	endpoint := pasteEndpoint
	if u := strings.TrimSpace(os.Getenv("MILLENNIUM_PASTE_URL")); u != "" {
		endpoint = u
	}
	req, err := http.NewRequest(http.MethodPost, endpoint, strings.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "text/plain; charset=utf-8")
	req.Header.Set("User-Agent", "millennium-helpers")
	resp, err := httpDo(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	b, err := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if err != nil {
		return "", err
	}
	url := strings.TrimSpace(string(b))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 || !strings.Contains(url, "http") {
		return "", fmt.Errorf("paste.rs returned HTTP %d: %s", resp.StatusCode, url)
	}
	return url, nil
}

// ShareReport builds, redacts, and uploads a diagnostic report.
func ShareReport(o Options) int {
	fmt.Println("Generating and uploading diagnostic report...")
	rep := Collect()
	var body string
	if o.JSON {
		body = FormatJSON(rep)
	} else {
		body = FormatReportFromCollect(rep)
	}
	sanitized := RedactReport(body)
	url, err := UploadPasteRS(sanitized)
	if err != nil {
		kept := keepFailedShare(sanitized)
		fmt.Fprintln(os.Stderr, "Error: Failed to upload diagnostic report to paste.rs.")
		if kept != "" {
			fmt.Fprintf(os.Stderr, "Local sanitized report kept at: %s\n", kept)
		}
		fmt.Fprintln(os.Stderr, "Tip: retry later, or paste the file contents into an offline pastebin.")
		return 1
	}
	fmt.Println("Diagnostic report successfully shared!")
	fmt.Printf("URL: %s\n", url)
	return 0
}

func keepFailedShare(body string) string {
	dir := schedule.StateDir()
	if err := os.MkdirAll(dir, 0o700); err != nil {
		dir = os.TempDir()
	}
	name := fmt.Sprintf("diag-share-failed-%s.txt", time.Now().Format("20060102150405"))
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		path = filepath.Join(os.TempDir(), name)
		if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
			return ""
		}
	}
	return path
}
