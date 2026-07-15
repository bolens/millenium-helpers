package install

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"runtime"
	"strings"
	"time"
)

// ResolvedTrack is the download plan for a helpers install track.
type ResolvedTrack struct {
	Track           string
	Ref             string
	Version         string
	URL             string
	SHAURL          string
	NeedsSHA        bool
	IsSourceArchive bool
}

// ResolveTrackURLs resolves release/main/tag download URLs (no download).
// checkout returns empty URL (use local source root).
func ResolveTrackURLs(track, tag, platform string) (ResolvedTrack, error) {
	track, tag, err := ValidateTrack(track, tag)
	if err != nil {
		return ResolvedTrack{}, err
	}
	out := ResolvedTrack{Track: track}
	if v := os.Getenv("MILLENNIUM_HELPERS_RELEASE_URL"); v != "" {
		out.URL = v
		out.SHAURL = envOr("MILLENNIUM_HELPERS_RELEASE_SHA_URL", v+".sha256")
		out.NeedsSHA = true
		switch track {
		case "tag":
			out.Ref = tag
			out.Version = strings.TrimPrefix(tag, "v")
		case "main":
			out.Ref = "main"
			out.IsSourceArchive = true
			out.NeedsSHA = false
		default:
			out.Ref = "latest"
		}
		return out, nil
	}
	repo := envOr("HELPERS_GITHUB_REPO", HelpersGitHubRepo)
	switch track {
	case "checkout":
		out.Ref = "checkout"
		return out, nil
	case "main":
		out.Ref = "main"
		out.IsSourceArchive = true
		if platform == "windows" {
			out.URL = fmt.Sprintf("https://github.com/%s/archive/refs/heads/main.zip", repo)
		} else {
			out.URL = fmt.Sprintf("https://github.com/%s/archive/refs/heads/main.tar.gz", repo)
		}
		return out, nil
	case "tag":
		out.Ref = tag
		out.Version = strings.TrimPrefix(tag, "v")
	case "release":
		latest, err := fetchLatestTag(repo)
		if err != nil {
			return out, err
		}
		out.Ref = latest
		out.Version = strings.TrimPrefix(latest, "v")
		tag = latest
	}
	asset, err := helpersBinAsset(out.Version, platform)
	if err != nil {
		return out, err
	}
	out.URL = fmt.Sprintf("https://github.com/%s/releases/download/%s/%s", repo, tag, asset)
	out.SHAURL = out.URL + ".sha256"
	out.NeedsSHA = true
	return out, nil
}

func helpersBinAsset(version, platform string) (string, error) {
	if platform == "windows" {
		return AssetHelpers(version, "windows", "amd64", "zip"), nil
	}
	arch, err := HostArch()
	if err != nil {
		return "", err
	}
	// Unix installer historically packs linux archives (darwin often via Homebrew).
	osName := "linux"
	if runtime.GOOS == "darwin" {
		osName = "darwin"
	}
	return AssetHelpers(version, osName, arch, "tar.gz"), nil
}

func fetchLatestTag(repo string) (string, error) {
	client := &http.Client{Timeout: 20 * time.Second}
	req, err := http.NewRequest(http.MethodGet, "https://api.github.com/repos/"+repo+"/releases/latest", nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", "millennium-helpers")
	req.Header.Set("Accept", "application/vnd.github+json")
	if tok := os.Getenv("GITHUB_TOKEN"); tok != "" {
		req.Header.Set("Authorization", "Bearer "+tok)
	}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("GitHub releases/latest: HTTP %d", resp.StatusCode)
	}
	var payload struct {
		TagName string `json:"tag_name"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		return "", err
	}
	if payload.TagName == "" {
		return "", fmt.Errorf("empty tag_name from GitHub")
	}
	return payload.TagName, nil
}
