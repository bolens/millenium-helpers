class MillenniumHelpersBin < Formula
  desc "Millennium helpers (prebuilt release assets) — scripts/MCP; Go dispatcher when embedded"
  homepage "https://github.com/bolens/millenium-helpers"
  url "https://github.com/bolens/millenium-helpers/releases/download/v2.6.2/millennium-helpers-linux.tar.gz"
  sha256 "c077c3f536e751e776fabb329600b18d7452d455a2e2dd1908491332569f4e55"
  license "MIT"

  depends_on "bash"
  depends_on "curl"
  depends_on "jq"
  depends_on "python"
  depends_on "unzip"

  conflicts_with "millennium-helpers", because: "both install the millennium helper tools"

  def install
    bin.install "scripts/millennium-repair.sh" => "millennium-repair"
    bin.install "scripts/millennium-upgrade.sh" => "millennium-upgrade"
    bin.install "scripts/millennium-schedule.sh" => "millennium-schedule"
    bin.install "scripts/millennium-purge.sh" => "millennium-purge"
    bin.install "scripts/millennium-diag.sh" => "millennium-diag"
    bin.install "scripts/millennium-theme.sh" => "millennium-theme"
    bin.install "scripts/millennium-mcp.py" => "millennium-mcp"
    if (buildpath/"bin/millennium").exist?
      bin.install "bin/millennium"
    else
      bin.install "scripts/millennium.sh" => "millennium"
    end

    (lib/"millennium-helpers").install "scripts/common.sh"
    (lib/"millennium-helpers/lib").install Dir["scripts/lib/*.sh"]

    commands = %w[
      millennium
      millennium-repair
      millennium-upgrade
      millennium-schedule
      millennium-purge
      millennium-diag
      millennium-theme
      millennium-mcp
    ]

    bash_completion.install "completions/bash/millennium-helpers" => "millennium-helpers"
    commands.each do |cmd|
      ln_sf "millennium-helpers", bash_completion/cmd
    end

    zsh_completion.install "completions/zsh/_millennium-helpers" => "_millennium-helpers"
    commands.each do |cmd|
      ln_sf "_millennium-helpers", zsh_completion/"_#{cmd}"
    end

    fish_completion.install Dir["completions/fish/*.fish"]
    (share/"nushell/completions").install "completions/nushell/millennium-helpers.nu"
    man1.install Dir["man/*.1"]
    (lib/"millennium-helpers").install "VERSION"

    license_md = "third_party/MILLENNIUM-LICENSE.md"
    (lib/"millennium-helpers").install license_md if File.exist?(license_md)
  end

  def caveats
    <<~EOS
      This formula installs the published release tarball.
      For a from-source build with `go`, use: millennium-helpers
    EOS
  end

  test do
    system "#{bin}/millennium-diag", "--help"
    assert_path_exists lib/"millennium-helpers/common.sh"
  end
end
