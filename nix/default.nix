{ lib
, stdenv
, makeWrapper
, bash
, curl
, unzip
, python3
, git
, go
, src
, version
, pname ? "millennium-helpers"
  # Release tarball is flat (multiple top-level dirs). Git/cleanSource is a directory.
, unpackFlat ? false
  # Build Go strangler dispatcher (from-source / git). -bin uses prebuilt if present.
, buildGoDispatcher ? false
}:

stdenv.mkDerivation ({
  inherit pname version src;

  nativeBuildInputs = [ makeWrapper ] ++ lib.optionals buildGoDispatcher [ go ];

  buildInputs = [ bash python3 curl unzip git ];

  dontBuild = !buildGoDispatcher;

  buildPhase = lib.optionalString buildGoDispatcher ''
    runHook preBuild
    export CGO_ENABLED=0
    make build
    runHook postBuild
  '';

  postPatch = ''
    # Shell checkout fallbacks may still mention the packaged common path.
    for f in scripts/millennium-*.sh; do
      [ -f "$f" ] || continue
      if grep -q '/usr/lib/millennium-helpers/common.sh' "$f"; then
        substituteInPlace "$f" \
          --replace-fail '/usr/lib/millennium-helpers/common.sh' "$out/lib/millennium-helpers/common.sh"
      fi
    done
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    if [ ! -x bin/millennium ]; then
      echo "error: Go dispatcher bin/millennium is required" >&2
      exit 1
    fi
    install -m755 bin/millennium $out/bin/millennium
    # Long-name PATH twins: inject subcommand (Nix wrappers change argv0).
    for pair in \
      "millennium-mcp:mcp" \
      "millennium-repair:repair" \
      "millennium-upgrade:upgrade" \
      "millennium-schedule:schedule" \
      "millennium-purge:purge" \
      "millennium-diag:diag" \
      "millennium-theme:theme"
    do
      twin="''${pair%%:*}"
      cmd="''${pair#*:}"
      makeWrapper $out/bin/millennium $out/bin/$twin \
        --add-flags "$cmd" \
        --prefix PATH : ${lib.makeBinPath [ bash python3 curl unzip git ]}
    done
    wrapProgram $out/bin/millennium \
      --prefix PATH : ${lib.makeBinPath [ bash python3 curl unzip git ]}

    mkdir -p $out/lib/millennium-helpers/lib
    install -m644 scripts/common.sh $out/lib/millennium-helpers/common.sh
    install -m644 scripts/lib/*.sh $out/lib/millennium-helpers/lib/

    mkdir -p $out/share/bash-completion/completions
    install -m644 completions/bash/millennium-helpers $out/share/bash-completion/completions/millennium-helpers
    for script in millennium-repair millennium-upgrade millennium-schedule millennium-purge millennium-diag millennium-theme millennium-mcp millennium; do
      ln -sf millennium-helpers $out/share/bash-completion/completions/$script
    done

    mkdir -p $out/share/zsh/site-functions
    install -m644 completions/zsh/_millennium-helpers $out/share/zsh/site-functions/_millennium-helpers
    for script in millennium-repair millennium-upgrade millennium-schedule millennium-purge millennium-diag millennium-theme millennium-mcp millennium; do
      ln -sf _millennium-helpers $out/share/zsh/site-functions/_$script
    done

    mkdir -p $out/share/fish/vendor_completions.d
    for f in completions/fish/*.fish; do
      install -m644 "$f" $out/share/fish/vendor_completions.d/
    done

    mkdir -p $out/share/nushell/completions
    install -m644 completions/nushell/millennium-helpers.nu $out/share/nushell/completions/millennium-helpers.nu

    mkdir -p $out/share/man/man1
    install -m644 man/*.1 $out/share/man/man1/

    install -m644 VERSION $out/lib/millennium-helpers/VERSION

    if [ -f third_party/MILLENNIUM-LICENSE.md ]; then
      install -m644 third_party/MILLENNIUM-LICENSE.md $out/lib/millennium-helpers/MILLENNIUM-LICENSE.md
    fi

    mkdir -p $out/share/licenses/${pname}
    install -m644 LICENSE $out/share/licenses/${pname}/LICENSE

    runHook postInstall
  '';

  meta = with lib; {
    description = "Cross-platform utility scripts and Model Context Protocol (MCP) server for managing, upgrading, diagnosing, and controlling Millennium on Linux";
    homepage = "https://github.com/bolens/millenium-helpers";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "millennium";
  };
} // lib.optionalAttrs unpackFlat {
  # Release asset has scripts/, completions/, man/, … at the archive root.
  unpackPhase = ''
    runHook preUnpack
    mkdir -p source
    tar -xzf "$src" -C source
    export sourceRoot=source
    chmod -R u+w -- "$sourceRoot"
    runHook postUnpack
  '';
})
