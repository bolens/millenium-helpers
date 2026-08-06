//go:build windows

package mcp

import (
	"os/exec"
	"strconv"
)

func prepareCommand(_ *exec.Cmd) {}

func killCommandTree(cmd *exec.Cmd) {
	if cmd.Process == nil {
		return
	}
	// taskkill /T terminates descendants as well as the direct process.
	_ = exec.Command(
		"taskkill", "/PID", strconv.Itoa(cmd.Process.Pid), "/T", "/F",
	).Run()
	_ = cmd.Process.Kill()
}
