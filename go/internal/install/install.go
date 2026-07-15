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

	sourceRoot, err := FindSourceRoot(o.SourceRoot)
	if err != nil {
		return res, err
	}
	o.SourceRoot = sourceRoot

	dispatcher, err := ResolveDispatcherBinary(sourceRoot, o.DispatcherSrc)
	if err != nil {
		return res, err
	}

	track := o.Track
	ref := o.Tag
	ver := strings.TrimSpace(version.Resolve())
	if InferCheckoutTrack(sourceRoot) && o.SourceURL == "" && (track == "release" || track == "") {
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
	if err := planCopy(dispatcher, destMain, 0o755, o.DryRun, &res.Plan); err != nil {
		return res, err
	}

	if runtime.GOOS == "windows" {
		if err := installWindowsExtras(o, dispatcher, &res); err != nil {
			return res, err
		}
	} else {
		for _, twin := range TwinNames() {
			dst := filepath.Join(o.TargetDir, twin)
			if err := planCopy(dispatcher, dst, 0o755, o.DryRun, &res.Plan); err != nil {
				return res, err
			}
		}
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

	res.Plan = append(res.Plan, "Millennium helpers install complete")
	return res, nil
}

func installUnixLibs(o Options, sourceRoot string, res *Result) error {
	common := filepath.Join(sourceRoot, "scripts", "common.sh")
	if _, err := os.Stat(common); err == nil {
		if err := planCopy(common, filepath.Join(o.LibDir, "common.sh"), 0o644, o.DryRun, &res.Plan); err != nil {
			return err
		}
	}
	libSrc := filepath.Join(sourceRoot, "scripts", "lib")
	libDst := filepath.Join(o.LibDir, "lib")
	if st, err := os.Stat(libSrc); err == nil && st.IsDir() {
		if err := ensureDir(libDst, o.DryRun, &res.Plan); err != nil {
			return err
		}
		if o.DryRun {
			res.Plan = append(res.Plan, "install scripts/lib/*.sh → "+libDst)
		} else {
			if err := copyTreeFiles(libSrc, libDst, "*.sh"); err != nil {
				return err
			}
		}
	}
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
	}

	res.Plan = append(res.Plan, "Millennium helpers uninstall complete")
	if o.Purge {
		res.Plan = append(res.Plan, "note: --purge requests client purge (run: millennium purge --yes)")
	}
	return res, nil
}
