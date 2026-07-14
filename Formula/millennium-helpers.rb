class MillenniumHelpers < Formula
  desc "Millennium helpers (from source) — Go strangler CLI plus shell helpers/MCP"
  homepage "https://github.com/bolens/millenium-helpers"
  url "https://github.com/bolens/millenium-helpers/releases/download/v2.6.2/millennium-helpers-v2.6.2-src.tar.gz"
  sha256 "65e4c76384f79f5e75838809a30369e8dd5150d7c61bcb6b093d05544ad2e419"
  license "MIT"
  head "https://github.com/bolens/millenium-helpers.git", branch: "main"

  depends_on "go" => :build
  depends_on "bash"
  depends_on "curl"
  depends_on "jq"
  depends_on "python"
  depends_on "unzip"

  def install
    system "make", "build"

    bin.install "scripts/millennium-repair.sh" => "millennium-repair"
    bin.install "scripts/millennium-upgrade.sh" => "millennium-upgrade"
    bin.install "scripts/millennium-schedule.sh" => "millennium-schedule"
    bin.install "scripts/millennium-purge.sh" => "millennium-purge"
    bin.install "scripts/millennium-diag.sh" => "millennium-diag"
    bin.install "scripts/millennium-theme.sh" => "millennium-theme"
    odie "Go dispatcher bin/millennium missing after make build" unless (buildpath/"bin/millennium").exist?
    bin.install "bin/millennium"
    bin.install_symlink "millennium" => "millennium-mcp"

    (lib/"millennium-helpers").install "scripts/common.sh"
    (lib/"millennium-helpers/lib").install Dir["scripts/lib/*.sh"]
    (lib/"millennium-helpers").install "scripts/millennium-mcp.py"

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
      To enable daily automated updates on macOS, run:
        millennium schedule enable

      For the prebuilt release-asset formula, see: millennium-helpers-bin

      Nushell completions are installed to:
        #{opt_share}/nushell/completions/millennium-helpers.nu
    EOS
  end

  test do
    system "#{bin}/millennium", "version"
    system "#{bin}/millennium-diag", "--help"
    assert_path_exists lib/"millennium-helpers/common.sh"
    assert_path_exists bash_completion/"millennium"
  end
end
