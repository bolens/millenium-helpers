package install

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// Options configure install / uninstall.
type Options struct {
	Action            string // install | uninstall
	Track             string
	Tag               string
	DryRun            bool
	Purge             bool // uninstall: also purge Millennium client
	AllowUnsignedMain bool
	Force             bool
	SkipWizard        bool
	TargetDir         string
	LibDir            string // Unix lib / Windows unused (meta under InstallRoot)
	InstallRoot       string // Windows: %USERPROFILE%\.millennium-helpers
	SourceRoot        string // checkout / extracted archive root
	SourceURL         string // recorded in meta (piped installs)
	DispatcherSrc     string // path to millennium binary to install; empty = resolve
}

// DefaultOptions fills OS defaults from the environment.
func DefaultOptions() Options {
	o := Options{
		Action: "install",
		Track:  envOr("MILLENNIUM_HELPERS_TRACK", "release"),
		Tag:    os.Getenv("MILLENNIUM_HELPERS_TAG"),
	}
	if v := os.Getenv("MILLENNIUM_HELPERS_ALLOW_UNSIGNED_MAIN"); v == "1" || strings.EqualFold(v, "true") {
		o.AllowUnsignedMain = true
	}
	o.SourceURL = os.Getenv("MILLENNIUM_HELPERS_SOURCE_URL")
	o.SourceRoot = os.Getenv("MILLENNIUM_SOURCE_ROOT")
	if runtime.GOOS == "windows" {
		home := os.Getenv("USERPROFILE")
		if home == "" {
			home, _ = os.UserHomeDir()
		}
		o.InstallRoot = filepath.Join(home, ".millennium-helpers")
		o.TargetDir = filepath.Join(o.InstallRoot, "bin")
		o.LibDir = o.InstallRoot
	} else {
		o.TargetDir = envOr("TARGET_DIR", "/usr/local/bin")
		o.LibDir = envOr("MILLENNIUM_LIB_DIR", "/usr/local/lib/millennium-helpers")
	}
	return o
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

// ParseArgs parses install/uninstall CLI args (after the subcommand name).
func ParseArgs(action string, args []string) (Options, error) {
	o := DefaultOptions()
	o.Action = action
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "-h" || a == "--help" || a == "-Help":
			return o, errHelp
		case a == "-V" || a == "--version" || a == "-Version":
			return o, errVersion
		case a == "-d" || a == "--dry-run" || a == "-DryRun":
			o.DryRun = true
		case a == "-p" || a == "--purge" || a == "-Purge":
			o.Purge = true
		case a == "-Force" || a == "--force" || a == "-f":
			o.Force = true
		case a == "--skip-wizard":
			o.SkipWizard = true
		case a == "--allow-unsigned-main" || a == "-AllowUnsignedMain":
			o.AllowUnsignedMain = true
		case a == "--track" || a == "-Track":
			i++
			if i >= len(args) {
				return o, fmt.Errorf("--track requires a value")
			}
			o.Track = args[i]
		case strings.HasPrefix(a, "--track="):
			o.Track = strings.TrimPrefix(a, "--track=")
		case a == "--tag" || a == "-Tag":
			i++
			if i >= len(args) {
				return o, fmt.Errorf("--tag requires a value")
			}
			o.Tag = args[i]
			o.Track = "tag"
		case strings.HasPrefix(a, "--tag="):
			o.Tag = strings.TrimPrefix(a, "--tag=")
			o.Track = "tag"
		case a == "--prefix" || a == "--target-dir":
			i++
			if i >= len(args) {
				return o, fmt.Errorf("%s requires a value", a)
			}
			o.TargetDir = args[i]
			if runtime.GOOS == "windows" {
				o.InstallRoot = filepath.Dir(o.TargetDir)
				o.LibDir = o.InstallRoot
			}
		case a == "--lib-dir":
			i++
			if i >= len(args) {
				return o, fmt.Errorf("--lib-dir requires a value")
			}
			o.LibDir = args[i]
		case a == "--source-root":
			i++
			if i >= len(args) {
				return o, fmt.Errorf("--source-root requires a value")
			}
			o.SourceRoot = args[i]
		case strings.HasPrefix(a, "-"):
			return o, fmt.Errorf("unknown option %q", a)
		default:
			return o, fmt.Errorf("unexpected argument %q", a)
		}
	}
	track, tag, err := ValidateTrack(o.Track, o.Tag)
	if err != nil {
		return o, err
	}
	o.Track = track
	o.Tag = tag
	return o, nil
}

var (
	errHelp    = fmt.Errorf("help")
	errVersion = fmt.Errorf("version")
)

// IsHelp reports whether ParseArgs returned the help sentinel.
func IsHelp(err error) bool { return err == errHelp }

// IsVersion reports whether ParseArgs returned the version sentinel.
func IsVersion(err error) bool { return err == errVersion }
