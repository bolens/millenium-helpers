//go:build windows

package schedule

func effectiveUID() int { return 1 } // non-root; Windows uses Task Scheduler elevation separately
