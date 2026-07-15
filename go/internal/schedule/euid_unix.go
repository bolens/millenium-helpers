//go:build unix

package schedule

import "os"

func effectiveUID() int { return os.Geteuid() }
