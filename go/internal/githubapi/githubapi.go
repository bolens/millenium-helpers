package githubapi

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

const (
	Owner = "SteamClientHomebrew"
	Repo  = "Millennium"
)

// Token returns GITHUB_TOKEN or helpers config github_token via env already loaded by caller.
func Token() string {
	return strings.TrimSpace(os.Getenv("GITHUB_TOKEN"))
}

func client() *http.Client {
	return &http.Client{Timeout: 45 * time.Second}
}

func apiGet(url string) ([]byte, error) {
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "millennium-helpers")
	req.Header.Set("Accept", "application/vnd.github+json")
	if tok := Token(); tok != "" {
		req.Header.Set("Authorization", "token "+tok)
	}
	resp, err := client().Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("GitHub API request failed (HTTP %d)", resp.StatusCode)
	}
	return body, nil
}

type release struct {
	TagName    string `json:"tag_name"`
	Prerelease bool   `json:"prerelease"`
}

// LatestTag returns the Millennium release tag for channel stable|beta|main.
func LatestTag(channel string) (string, error) {
	switch channel {
	case "stable", "":
		body, err := apiGet(fmt.Sprintf("https://api.github.com/repos/%s/%s/releases/latest", Owner, Repo))
		if err != nil {
			return "", err
		}
		var r release
		if err := json.Unmarshal(body, &r); err != nil {
			return "", err
		}
		return r.TagName, nil
	case "beta", "main":
		body, err := apiGet(fmt.Sprintf("https://api.github.com/repos/%s/%s/releases", Owner, Repo))
		if err != nil {
			return "", err
		}
		var releases []release
		if err := json.Unmarshal(body, &releases); err != nil {
			return "", err
		}
		if channel == "beta" {
			for _, r := range releases {
				if r.Prerelease && strings.Contains(strings.ToLower(r.TagName), "beta") {
					return r.TagName, nil
				}
			}
			return "", fmt.Errorf("no beta prerelease found")
		}
		// main: newest non-beta prerelease, else any prerelease
		for _, r := range releases {
			if r.Prerelease && !strings.Contains(strings.ToLower(r.TagName), "beta") {
				return r.TagName, nil
			}
		}
		for _, r := range releases {
			if r.Prerelease {
				return r.TagName, nil
			}
		}
		return "", fmt.Errorf("no tip-of-development prerelease found")
	default:
		return "", fmt.Errorf("invalid channel %q", channel)
	}
}

// LinuxArchiveNames returns tarball and checksum asset names for a version (no leading v in ver).
func LinuxArchiveNames(ver string) (archive, shaFile string) {
	ver = strings.TrimPrefix(ver, "v")
	archive = fmt.Sprintf("millennium-v%s-linux-x86_64.tar.gz", ver)
	shaFile = fmt.Sprintf("millennium-v%s-linux-x86_64.sha256", ver)
	return archive, shaFile
}

// WindowsArchiveNames returns zip and checksum asset names for a version (no leading v in ver).
func WindowsArchiveNames(ver string) (archive, shaFile string) {
	ver = strings.TrimPrefix(ver, "v")
	archive = fmt.Sprintf("millennium-v%s-windows-x86_64.zip", ver)
	shaFile = fmt.Sprintf("millennium-v%s-windows-x86_64.sha256", ver)
	return archive, shaFile
}

// ReleaseDownloadURL builds a GitHub release asset URL.
func ReleaseDownloadURL(tag, asset string) string {
	tag = strings.TrimSpace(tag)
	if !strings.HasPrefix(tag, "v") {
		tag = "v" + tag
	}
	return fmt.Sprintf("https://github.com/%s/%s/releases/download/%s/%s", Owner, Repo, tag, asset)
}

// FetchFirstFieldSHA downloads a .sha256 file and returns the first whitespace-separated field.
func FetchFirstFieldSHA(shaURL string) (string, error) {
	req, err := http.NewRequest(http.MethodGet, shaURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", "millennium-helpers")
	if tok := Token(); tok != "" {
		req.Header.Set("Authorization", "token "+tok)
	}
	resp, err := client().Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("checksum download failed (HTTP %d)", resp.StatusCode)
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if err != nil {
		return "", err
	}
	fields := strings.Fields(string(b))
	if len(fields) == 0 {
		return "", fmt.Errorf("empty checksum file")
	}
	return fields[0], nil
}

// Download writes url to destPath.
func Download(url, destPath string) error {
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "millennium-helpers")
	if tok := Token(); tok != "" {
		req.Header.Set("Authorization", "token "+tok)
	}
	resp, err := client().Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("download failed (HTTP %d)", resp.StatusCode)
	}
	f, err := os.Create(destPath)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = io.Copy(f, resp.Body)
	return err
}
