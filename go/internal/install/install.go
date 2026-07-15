package install

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/bolens/millenium-helpers/internal/version"
)

// Result summarizes a dry-run or live install/uninstall.
type Result struct {
	Plan []string
}

// Run executes install or uninstall per Options.
func Run(o Options) (Result, error) {
	switch o.Action {
	case "install":
		return runInstall(o)
	case "uninstall":
		return runUninstall(o)
	default:
		return Result{}, fmt.Errorf("unknown action %q", o.Action)
	}
}

func runInstall(o Options) (Result, error) {
	var res Result
	if o.DryRun {
		res.Plan = append(res.Plan, "DRY RUN MODE: No changes will be made")
	}

	sourceRoot, cleanup, resolved, fromNetwork, err := prepareSource(o, &res)
	if cleanup != nil {
		defer cleanup()
	}
	if err != nil {
		return res, err
	}
	o.SourceRoot = sourceRoot

	track := o.Track
	ref := o.Tag
	ver := strings.TrimSpace(version.Resolve())
	if fromNetwork {
		track = resolved.Track
		ref = resolved.Ref
		if resolved.Version != "" {
			ver = resolved.Version
		}
		if o.SourceURL == "" {
			o.SourceURL = resolved.URL
		}
	} else if InferCheckoutTrack(sourceRoot) && o.SourceURL == "" && (track == "release" || track == "") {
		track = "checkout"
		if short, err := runGitRevParse(sourceRoot); err == nil && short != "" {
			ref = short
		} else {
			ref = "checkout"
		}
	} else if track == "tag" {
		ref = o.Tag
		ver = strings.TrimPrefix(o.Tag, "v")
	} else if track == "main" {
		ref = "main"
	} else if track == "release" {
		if ref == "" {
			ref = "latest"
			if ver != "" {
				ref = "v" + strings.TrimPrefix(ver, "v")
			}
		}
	}

	if err := ensureDir(o.TargetDir, o.DryRun, &res.Plan); err != nil {
		return res, err
	}
	metaRoot := o.LibDir
	if runtime.GOOS == "windows" {
		if o.InstallRoot == "" {
			o.InstallRoot = filepath.Dir(o.TargetDir)
		}
		metaRoot = o.InstallRoot
		if err := ensureDir(o.InstallRoot, o.DryRun, &res.Plan); err != nil {
			return res, err
		}
	} else if err := ensureDir(o.LibDir, o.DryRun, &res.Plan); err != nil {
		return res, err
	}

	exeName := "millennium"
	if runtime.GOOS == "windows" {
		exeName = "millennium.exe"
	}
	destMain := filepath.Join(o.TargetDir, exeName)

	// Dry-run with network plan only (no local/extracted tree): destinations only.
	if o.DryRun && sourceRoot == "" {
		res.Plan = append(res.Plan, "install binary -> "+destMain)
		res.Plan = append(res.Plan, "write "+MetaPath(metaRoot))
		res.Plan = append(res.Plan, "Millennium helpers install complete")
		return res, nil
	}

	dispatcher, err := ResolveDispatcherBinary(sourceRoot, o.DispatcherSrc)
	if err != nil {
		return res, err
	}
	if err := planCopy(dispatcher, destMain, 0o755, o.DryRun, &res.Plan); err != nil {
		return res, err
	}

	if runtime.GOOS == "windows" {
		if err := installWindowsExtras(o, dispatcher, &res); err != nil {
			return res, err
		}
		if err := installWindowsPATH(o, &res); err != nil {
			return res, err
		}
		if err := installWindowsCompletionHooks(o, &res); err != nil {
			return res, err
		}
	} else {
		if err := installUnixLibs(o, sourceRoot, &res); err != nil {
			return res, err
		}
		if err := installUnixCompletionsAndMan(o, sourceRoot, &res); err != nil {
			return res, err
		}
	}

	meta := Meta{
		Track:     track,
		Ref:       ref,
		Version:   ver,
		SourceURL: o.SourceURL,
	}
	res.Plan = append(res.Plan, "write "+MetaPath(metaRoot))
	if !o.DryRun {
		if err := WriteMeta(metaRoot, meta); err != nil {
			return res, err
		}
	}

	if err := installSudoers(o, &res); err != nil {
		return res, err
	}

	res.Plan = append(res.Plan, "Millennium helpers install complete")
	return res, nil
}

// prepareSource finds a local helpers tree or downloads one for the selected track.
func prepareSource(o Options, res *Result) (sourceRoot string, cleanup func(), resolved ResolvedTrack, fromNetwork bool, err error) {
	cleanup = func() {}
	if o.SourceRoot != "" {
		root, e := FindSourceRoot(o.SourceRoot)
		return root, cleanup, resolved, false, e
	}
	if root, e := FindSourceRoot(""); e == nil {
		return root, cleanup, resolved, false, nil
	}

	if o.Track == "checkout" {
		return "", cleanup, resolved, false, fmt.Errorf("could not find helpers source root for track=checkout (set --source-root)")
	}

	platform := "linux"
	if runtime.GOOS == "windows" {
		platform = "windows"
	}
	resolved, err = ResolveTrackURLs(o.Track, o.Tag, platform)
	if err != nil {
		return "", cleanup, resolved, false, err
	}
	if resolved.Track == "main" && !o.AllowUnsignedMain {
		return "", cleanup, resolved, false, fmt.Errorf("track main requires --allow-unsigned-main (unsigned tip-of-main archive)")
	}
	res.Plan = append(res.Plan, "download "+resolved.URL)
	if resolved.NeedsSHA {
		res.Plan = append(res.Plan, "verify sha256 "+resolved.SHAURL)
	}
	if o.DryRun {
		return "", cleanup, resolved, true, nil
	}
	root, tmp, resolved, err := FetchHelpersTree(o)
	if err != nil {
		return "", cleanup, resolved, true, err
	}
	cleanup = func() { _ = os.RemoveAll(tmp) }
	return root, cleanup, resolved, true, nil
}

func installUnixLibs(o Options, sourceRoot string, res *Result) error {
	verSrc := filepath.Join(sourceRoot, "VERSION")
	if _, err := os.Stat(verSrc); err == nil {
		if err := planCopy(verSrc, filepath.Join(o.LibDir, "VERSION"), 0o644, o.DryRun, &res.Plan); err != nil {
			return err
		}
	}
	lic := filepath.Join(sourceRoot, "third_party", "MILLENNIUM-LICENSE.md")
	if _, err := os.Stat(lic); err == nil {
		if err := planCopy(lic, filepath.Join(o.LibDir, "MILLENNIUM-LICENSE.md"), 0o644, o.DryRun, &res.Plan); err != nil {
			return err
		}
	}
	return nil
}

func runUninstall(o Options) (Result, error) {
	var res Result
	if o.DryRun {
		res.Plan = append(res.Plan, "DRY RUN MODE: No changes will be made")
	}

	exeName := "millennium"
	if runtime.GOOS == "windows" {
		exeName = "millennium.exe"
	}
	_ = planRemove(filepath.Join(o.TargetDir, exeName), o.DryRun, &res.Plan)
	if runtime.GOOS == "windows" {
		removeWindowsPATH(o, &res)
		removeWindowsCompletionHooks(o, &res)
		for _, twin := range TwinNames() {
			_ = planRemove(filepath.Join(o.TargetDir, twin+".cmd"), o.DryRun, &res.Plan)
		}
		_ = planRemove(filepath.Join(o.TargetDir, "common.ps1"), o.DryRun, &res.Plan)
		_ = planRemove(filepath.Join(o.TargetDir, "lib"), o.DryRun, &res.Plan)
		_ = planRemove(filepath.Join(o.TargetDir, "millennium-helpers.completion.ps1"), o.DryRun, &res.Plan)
		root := o.InstallRoot
		if root == "" {
			root = filepath.Dir(o.TargetDir)
		}
		_ = planRemove(root, o.DryRun, &res.Plan)
	} else {
		for _, twin := range TwinNames() {
			_ = planRemove(filepath.Join(o.TargetDir, twin), o.DryRun, &res.Plan)
		}
		_ = planRemove(o.LibDir, o.DryRun, &res.Plan)
		removeUnixCompletionsAndMan(o, &res)
		removeSudoers(o, &res)
	}

	res.Plan = append(res.Plan, "Millennium helpers uninstall complete")
	if o.Purge {
		res.Plan = append(res.Plan, "note: --purge requests client purge (run: millennium purge --yes)")
	}
	return res, nil
}
