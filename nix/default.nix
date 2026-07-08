{ lib
, stdenv
, makeWrapper
, bash
, curl
, unzip
, python3
, git
}:

stdenv.mkDerivation rec {
  pname = "millennium-helpers";
  version = "0.1.0";

  src = ../.;

  nativeBuildInputs = [ makeWrapper ];

  buildInputs = [ bash python3 curl unzip git ];

  dontBuild = true;

  postPatch = ''
    for f in scripts/millennium-*.sh; do
      substituteInPlace "$f" \
        --replace '/usr/lib/millennium-helpers/common.sh' "$out/lib/millennium-helpers/common.sh"
    done
  '';

  installPhase = ''
    runHook preInstall

    # Install scripts
    mkdir -p $out/bin
    install -m755 scripts/millennium-repair.sh $out/bin/millennium-repair
    install -m755 scripts/millennium-upgrade.sh $out/bin/millennium-upgrade
    install -m755 scripts/millennium-schedule.sh $out/bin/millennium-schedule
    install -m755 scripts/millennium-purge.sh $out/bin/millennium-purge
    install -m755 scripts/millennium-diag.sh $out/bin/millennium-diag
    install -m755 scripts/millennium-theme.sh $out/bin/millennium-theme
    install -m755 scripts/millennium-mcp.py $out/bin/millennium-mcp

    # Install shared library and its modules
    mkdir -p $out/lib/millennium-helpers/lib
    install -m644 scripts/common.sh $out/lib/millennium-helpers/common.sh
    install -m644 scripts/lib/*.sh $out/lib/millennium-helpers/lib/

    # Wrap the scripts to ensure they have the runtime dependencies on PATH
    for script in millennium-repair millennium-upgrade millennium-schedule millennium-purge millennium-diag millennium-theme millennium-mcp; do
      wrapProgram $out/bin/$script \
        --prefix PATH : ${lib.makeBinPath [ bash python3 curl unzip git ]}
    done

    # Install completions
    mkdir -p $out/share/bash-completion/completions
    install -m644 completions/bash/millennium-helpers $out/share/bash-completion/completions/millennium-helpers
    for script in millennium-repair millennium-upgrade millennium-schedule millennium-purge millennium-diag millennium-theme millennium-mcp; do
      ln -sf millennium-helpers $out/share/bash-completion/completions/$script
    done

    mkdir -p $out/share/zsh/site-functions
    install -m644 completions/zsh/_millennium-helpers $out/share/zsh/site-functions/_millennium-helpers
    for script in millennium-repair millennium-upgrade millennium-schedule millennium-purge millennium-diag millennium-theme millennium-mcp; do
      ln -sf _millennium-helpers $out/share/zsh/site-functions/_$script
    done

    mkdir -p $out/share/fish/vendor_completions.d
    for f in completions/fish/*.fish; do
      install -m644 "$f" $out/share/fish/vendor_completions.d/
    done

    mkdir -p $out/share/nushell/completions
    install -m644 completions/nushell/millennium-helpers.nu $out/share/nushell/completions/millennium-helpers.nu

    # Install license
    mkdir -p $out/share/licenses/millennium-helpers
    install -m644 LICENSE $out/share/licenses/millennium-helpers/LICENSE

    runHook postInstall
  '';

  meta = with lib; {
    description = "Utility scripts for managing, repairing, upgrading, rolling back, viewing logs, managing themes, and scheduling updates for Millennium on Linux";
    homepage = "https://github.com/bolens/millenium-helpers";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
