package steam

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"golang.org/x/term"
)

// ConfirmClose prompts (when interactive) then closes Steam gracefully.
// yes skips the prompt. Returns an error if the user declines or a game is running.
func ConfirmClose(yes bool) error {
	if IsGameRunning() {
		return fmt.Errorf("Error: A Steam game is currently running.\nClose the running game, then re-run. Use --yes to skip the Steam close prompt.")
	}
	if !IsSteamRunning() {
		return nil
	}

	assumeYes := yes ||
		os.Getenv("TEST_SUITE_RUN") != "" ||
		os.Getenv("PSTESTS") != ""

	interactive := false
	if !assumeYes {
		if os.Getenv("CONFIRM_CLOSE_FORCE_PROMPT") != "" {
			interactive = true
		} else if term.IsTerminal(int(os.Stdin.Fd())) {
			interactive = true
		}
	}

	if !assumeYes && interactive {
		fmt.Fprintln(os.Stderr, "Steam is running and must be closed to continue.")
		fmt.Fprint(os.Stderr, "Close Steam now? [y/N] ")
		line, _ := bufio.NewReader(os.Stdin).ReadString('\n')
		reply := strings.TrimSpace(strings.ToLower(line))
		if reply != "y" && reply != "yes" {
			return fmt.Errorf("Error: Aborted: Steam must be closed to continue. Re-run with --yes to skip this prompt.")
		}
	} else if !assumeYes {
		// Non-interactive without --yes: fail closed (doctor/repair/purge style).
		return fmt.Errorf("Error: Steam is running. Close Steam, or re-run with --yes (-y) to stop Steam and continue.")
	}

	username, home, err := TargetUser()
	if err != nil {
		return err
	}
	return CloseGracefully(username, home)
}
