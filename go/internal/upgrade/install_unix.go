//go:build unix

package upgrade

import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

func installPlatform(archivePath, version string, o Options) error {
	tmp, err := os.MkdirTemp("", "millennium-install-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)

	if err := extractTarGz(archivePath, tmp); err != nil {
		return err
	}
	src := filepath.Join(tmp, "usr", "lib", "millennium")
	if st, err := os.Stat(src); err != nil || !st.IsDir() {
		src = tmp
	}

	dest := InstallRoot()
	destTmp := dest + ".tmp"
	_ = os.RemoveAll(destTmp)
	if err := os.MkdirAll(destTmp, 0o755); err != nil {
		return err
	}
	if err := copyTreeFiles(src, destTmp); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(destTmp, "version.txt"), []byte(version+"\n"), 0o644); err != nil {
		return err
	}
	InstallLicense(destTmp)
	writeChecksums(destTmp)

	oldVer := "unknown"
	if b, err := os.ReadFile(filepath.Join(dest, "version.txt")); err == nil {
		oldVer = strings.TrimSpace(string(b))
	}
	if oldVer == "" || oldVer == "unknown" {
		oldVer = InferVersion(archivePath, version)
	}
	destBak := filepath.Join(filepath.Dir(dest), "millennium.bak_"+oldVer)
	if st, err := os.Stat(dest); err == nil && st.IsDir() {
		_ = os.RemoveAll(destBak)
		if err := os.Rename(dest, destBak); err != nil {
			return err
		}
	}
	if err := os.Rename(destTmp, dest); err != nil {
		if st, e := os.Stat(destBak); e == nil && st.IsDir() {
			_ = os.Rename(destBak, dest)
		}
		return err
	}
	PruneBackups()
	linkHooksCurrentUser(o.AllUsers)
	_ = runtime.GOOS
	return nil
}

func extractTarGz(archivePath, dest string) error {
	f, err := os.Open(archivePath)
	if err != nil {
		return err
	}
	defer f.Close()
	gz, err := gzip.NewReader(f)
	if err != nil {
		return fmt.Errorf("not a gzip archive: %w", err)
	}
	defer gz.Close()
	tr := tar.NewReader(gz)
	destAbs, _ := filepath.Abs(dest)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		name := filepath.Clean(hdr.Name)
		if strings.HasPrefix(name, "..") || filepath.IsAbs(name) {
			return fmt.Errorf("refusing unsafe tar member %q", hdr.Name)
		}
		target := filepath.Join(destAbs, name)
		if !strings.HasPrefix(target, destAbs+string(os.PathSeparator)) && target != destAbs {
			return fmt.Errorf("refusing tar slip member %q", hdr.Name)
		}
		switch hdr.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, 0o755); err != nil {
				return err
			}
		case tar.TypeReg, tar.TypeRegA:
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			out, err := os.OpenFile(target, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, hdr.FileInfo().Mode())
			if err != nil {
				return err
			}
			if _, err := io.Copy(out, tr); err != nil {
				_ = out.Close()
				return err
			}
			_ = out.Close()
		}
	}
	return nil
}

func copyTreeFiles(src, dst string) error {
	return filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, path)
		if err != nil || rel == "." {
			if info.IsDir() {
				return nil
			}
		}
		target := filepath.Join(dst, rel)
		if info.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		in, err := os.Open(path)
		if err != nil {
			return err
		}
		defer in.Close()
		mode := info.Mode()
		if mode&0o111 != 0 {
			mode = 0o755
		} else {
			mode = 0o644
		}
		out, err := os.OpenFile(target, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, mode)
		if err != nil {
			return err
		}
		_, copyErr := io.Copy(out, in)
		closeErr := out.Close()
		if copyErr != nil {
			return copyErr
		}
		return closeErr
	})
}

func writeChecksums(dir string) {
	names := []string{
		"libmillennium_bootstrap_x86.so",
		"libmillennium_bootstrap_hhx64.so",
		"libmillennium_x86.so",
		"libmillennium_hhx64.so",
		"libmillennium_pvs64",
	}
	var b strings.Builder
	for _, n := range names {
		p := filepath.Join(dir, n)
		f, err := os.Open(p)
		if err != nil {
			continue
		}
		h := sha256.New()
		_, _ = io.Copy(h, f)
		_ = f.Close()
		b.WriteString(hex.EncodeToString(h.Sum(nil)))
		b.WriteString("  ")
		b.WriteString(n)
		b.WriteByte('\n')
	}
	if b.Len() > 0 {
		_ = os.WriteFile(filepath.Join(dir, "checksums.txt"), []byte(b.String()), 0o644)
	}
}

func linkHooksCurrentUser(allUsers bool) {
	if runtime.GOOS == "darwin" {
		return
	}
	homes := []string{}
	if home, err := os.UserHomeDir(); err == nil {
		homes = append(homes, home)
	}
	_ = allUsers // multi-UID enumeration deferred; current user covers default path
	for _, home := range homes {
		linkHooksForHome(home)
	}
}

func linkHooksForHome(home string) {
	var steam string
	for _, cand := range []string{
		filepath.Join(home, ".local/share/Steam"),
		filepath.Join(home, ".steam/steam"),
		filepath.Join(home, ".steam/root"),
		filepath.Join(home, ".var/app/com.valvesoftware.Steam/.local/share/Steam"),
	} {
		if st, err := os.Stat(cand); err == nil && st.IsDir() {
			steam = cand
			break
		}
	}
	if steam == "" {
		return
	}
	root := InstallRoot()
	_ = os.MkdirAll(filepath.Join(steam, "ubuntu12_32"), 0o755)
	_ = os.MkdirAll(filepath.Join(steam, "ubuntu12_64"), 0o755)
	forceSymlink(filepath.Join(root, "libmillennium_bootstrap_x86.so"), filepath.Join(steam, "ubuntu12_32", "libXtst.so.6"))
	forceSymlink(filepath.Join(root, "libmillennium_bootstrap_hhx64.so"), filepath.Join(steam, "ubuntu12_64", "libXtst.so.6"))
}

func forceSymlink(target, link string) {
	_ = os.Remove(link)
	_ = os.Symlink(target, link)
}
