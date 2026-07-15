package install

import (
	"fmt"
	"os"
	"strings"

	"github.com/bolens/millenium-helpers/internal/version"
)

const usageInstall = `Usage: millennium install [options]

Install Millennium helpers (Go dispatcher, PATH twins, completions, install libs).

Options:
  --track release|main|tag|checkout   Helpers install track (default: release)
  --tag vX.Y.Z                        Install a specific release tag
  --allow-unsigned-main               Allow tip-of-main unsigned archive
  --prefix DIR / --target-dir DIR     Binary install directory
  --lib-dir DIR                       Unix lib directory (install-meta + libs)
  --source-root DIR                   Checkout / extracted archive root
  --skip-wizard                       Do not launch schedule setup
  -d, --dry-run                       Print actions without writing
  -h, --help                          Show this help
  -V, --version                       Show version
`

const usageUninstall = `Usage: millennium uninstall [options]

Remove Millennium helpers installed by millennium install.

Options:
  -p, --purge                         Also purge Millennium client (hint only in MVP)
  --prefix DIR / --target-dir DIR     Binary install directory
  --lib-dir DIR                       Unix lib directory
  -d, --dry-run                       Print actions without writing
  -h, --help                          Show this help
  -V, --version                       Show version
`

// RunCLI parses args for action ("install"|"uninstall") and runs.
func RunCLI(action string, args []string) int {
	o, err := ParseArgs(action, args)
	if IsHelp(err) {
		if action == "uninstall" {
			fmt.Print(usageUninstall)
		} else {
			fmt.Print(usageInstall)
		}
		return 0
	}
	if IsVersion(err) {
		version.Print("millennium-" + action)
		return 0
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err.Error())
		return 1
	}
	res, err := Run(o)
	for _, line := range res.Plan {
		fmt.Println(line)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err.Error())
		return 1
	}
	return 0
}

// UsageSnippet is listed from root help.
func UsageSnippet() string {
	return strings.TrimSpace(`install / uninstall — manage helpers on this machine`)
}
