//go:build unix

package steam

import (
	"os"
	"os/user"
	"strconv"
	"syscall"
)

func fileOwner(path string) (string, error) {
	st, err := os.Stat(path)
	if err != nil {
		return "", err
	}
	stat, ok := st.Sys().(*syscall.Stat_t)
	if !ok {
		return "", nil
	}
	u, err := user.LookupId(strconv.FormatUint(uint64(stat.Uid), 10))
	if err != nil {
		return "", err
	}
	return u.Username, nil
}

func chownUser(path, username string) {
	u, err := user.Lookup(username)
	if err != nil {
		return
	}
	uid, err1 := strconv.Atoi(u.Uid)
	gid, err2 := strconv.Atoi(u.Gid)
	if err1 != nil || err2 != nil {
		return
	}
	_ = os.Chown(path, uid, gid)
}

func effectiveUID() int { return os.Geteuid() }
