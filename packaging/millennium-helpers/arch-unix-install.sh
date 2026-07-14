# shellcheck shell=bash
# Shared Arch package() body for Unix helpers (from-source / -git / -bin).
# Caller must set:
#   pkgdir  — package root
#   pkgname — package name (for license path)
# And cwd to the extracted helpers tree (scripts/, completions/, …).
# Optional: MILLENNIUM_ARCH_DISPATCHER=/path/to/go-binary (else bin/millennium, else shell).

_arch_install_unix_helpers() {
  local dispatcher=""
  if [[ -n "${MILLENNIUM_ARCH_DISPATCHER:-}" && -x "${MILLENNIUM_ARCH_DISPATCHER}" ]]; then
    dispatcher="${MILLENNIUM_ARCH_DISPATCHER}"
  elif [[ -x bin/millennium ]]; then
    dispatcher="bin/millennium"
  else
    dispatcher="scripts/millennium.sh"
  fi

  install -d "${pkgdir}/usr/bin"
  install -m755 scripts/millennium-repair.sh "${pkgdir}/usr/bin/millennium-repair"
  install -m755 scripts/millennium-upgrade.sh "${pkgdir}/usr/bin/millennium-upgrade"
  install -m755 scripts/millennium-schedule.sh "${pkgdir}/usr/bin/millennium-schedule"
  install -m755 scripts/millennium-purge.sh "${pkgdir}/usr/bin/millennium-purge"
  install -m755 scripts/millennium-diag.sh "${pkgdir}/usr/bin/millennium-diag"
  install -m755 scripts/millennium-theme.sh "${pkgdir}/usr/bin/millennium-theme"
  install -m755 scripts/millennium-mcp.py "${pkgdir}/usr/bin/millennium-mcp"
  install -m755 "${dispatcher}" "${pkgdir}/usr/bin/millennium"

  install -d "${pkgdir}/usr/lib/millennium-helpers/lib"
  install -m644 scripts/common.sh "${pkgdir}/usr/lib/millennium-helpers/common.sh"
  install -m644 scripts/lib/*.sh "${pkgdir}/usr/lib/millennium-helpers/lib/"

  install -Dm644 completions/bash/millennium-helpers "${pkgdir}/usr/share/bash-completion/completions/millennium-helpers"
  local script
  for script in millennium-repair millennium-upgrade millennium-schedule millennium-purge millennium-diag millennium-theme millennium-mcp millennium; do
    ln -sf millennium-helpers "${pkgdir}/usr/share/bash-completion/completions/${script}"
  done

  install -Dm644 completions/zsh/_millennium-helpers "${pkgdir}/usr/share/zsh/site-functions/_millennium-helpers"
  for script in millennium-repair millennium-upgrade millennium-schedule millennium-purge millennium-diag millennium-theme millennium-mcp millennium; do
    ln -sf _millennium-helpers "${pkgdir}/usr/share/zsh/site-functions/_${script}"
  done

  install -d "${pkgdir}/usr/share/fish/vendor_completions.d"
  install -m644 completions/fish/*.fish "${pkgdir}/usr/share/fish/vendor_completions.d/"

  install -Dm644 completions/nushell/millennium-helpers.nu "${pkgdir}/usr/share/nushell/completions/millennium-helpers.nu"

  install -d "${pkgdir}/usr/share/man/man1"
  install -m644 man/*.1 "${pkgdir}/usr/share/man/man1/"

  install -Dm644 VERSION "${pkgdir}/usr/lib/millennium-helpers/VERSION"

  if [[ -f third_party/MILLENNIUM-LICENSE.md ]]; then
    install -Dm644 third_party/MILLENNIUM-LICENSE.md \
      "${pkgdir}/usr/lib/millennium-helpers/MILLENNIUM-LICENSE.md"
  fi

  install -Dm644 LICENSE "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
}

_arch_prepare_manual_conflict_check() {
  local conflict=0
  if [ -f "/usr/local/bin/millennium-repair" ] \
    || { [ -f "/etc/sudoers.d/millennium-helpers" ] && ! pacman -Qo "/etc/sudoers.d/millennium-helpers" &>/dev/null; }; then
    conflict=1
  fi
  local f
  for f in \
    /usr/share/fish/vendor_completions.d/millennium.fish \
    /usr/share/fish/vendor_completions.d/millennium-*.fish \
    /usr/share/bash-completion/completions/millennium \
    /usr/share/bash-completion/completions/millennium-* \
    /usr/share/zsh/site-functions/_millennium \
    /usr/share/zsh/site-functions/_millennium-* \
    /usr/share/nushell/completions/millennium-helpers.nu \
    /usr/share/man/man1/millennium.1 \
    /usr/share/man/man1/millennium-*.1
  do
    [ -e "$f" ] || continue
    if ! pacman -Qo "$f" &>/dev/null; then
      conflict=1
      break
    fi
  done

  if [ "$conflict" -eq 1 ]; then
    error "A manual installation of millennium-helpers was detected."
    plain "To avoid file conflicts, please uninstall the manual installation first by running:"
    plain "  sudo ./install.sh -u  (from the root of the source directory)"
    plain ""
    plain "If you no longer have the source directory, you can manually remove the conflicting files:"
    plain '  sudo rm -f /etc/sudoers.d/millennium-helpers'
    plain '  sudo rm -f /usr/local/bin/millennium /usr/local/bin/millennium-*'
    plain '  sudo rm -rf /usr/local/lib/millennium-helpers'
    plain '  sudo rm -f /usr/share/bash-completion/completions/millennium /usr/share/bash-completion/completions/millennium-*'
    plain '  sudo rm -f /usr/share/zsh/site-functions/_millennium /usr/share/zsh/site-functions/_millennium-*'
    plain '  sudo rm -f /usr/share/fish/vendor_completions.d/millennium.fish /usr/share/fish/vendor_completions.d/millennium-*.fish'
    plain '  sudo rm -f /usr/share/nushell/completions/millennium-helpers.nu'
    plain '  sudo rm -f /usr/share/man/man1/millennium.1 /usr/share/man/man1/millennium-*.1'
    plain '  sudo rm -f /usr/local/share/man/man1/millennium.1 /usr/local/share/man/man1/millennium-*.1'
    exit 1
  fi
}
