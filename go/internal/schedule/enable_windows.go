//go:build windows

package schedule

import (
	"fmt"
	"os"
)

func runEnable(channel string, useCron, dryRun, quiet bool) int {
	_ = useCron
	_ = quiet
	if dryRun {
		fmt.Printf("[DRY RUN] Would register Task Scheduler task %s (channel %s)\n", WinTaskName, channel)
		fmt.Println("Dry run: Scheduled task enablement simulated successfully.")
		return 0
	}
	fmt.Fprintln(os.Stderr, "Error: native live schedule enable on Windows is not implemented; use legacy or MILLENNIUM_LEGACY=1.")
	return 1
}

func runDisable(dryRun, quiet bool) int {
	_ = quiet
	if dryRun {
		fmt.Printf("[DRY RUN] Would unregister Task Scheduler task %s\n", WinTaskName)
		fmt.Println("Dry run: Scheduled task disablement simulated successfully.")
		return 0
	}
	fmt.Fprintln(os.Stderr, "Error: native live schedule disable on Windows is not implemented; use legacy or MILLENNIUM_LEGACY=1.")
	return 1
}
