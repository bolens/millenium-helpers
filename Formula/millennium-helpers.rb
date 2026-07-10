class MillenniumHelpers < Formula
  desc "Cross-platform utilities and MCP server for Millennium Steam Client hook"
  homepage "https://github.com/bolens/millenium-helpers"
  url "https://github.com/bolens/millenium-helpers/releases/download/v2.6.0/millennium-helpers-linux.tar.gz"
  sha256 "ff0321cf4032fb4b54682183a12686cbf8147a66be2e35109e14365515f9e2e3"
  license "MIT"
  head "https://github.com/bolens/millenium-helpers.git", branch: "main"

  depends_on "bash"
  depends_on "curl"
  depends_on "jq"
  depends_on "python"
  depends_on "unzip"

  def install
    # Install scripts
    bin.install "scripts/millennium-repair.sh" => "millennium-repair"
    bin.install "scripts/millennium-upgrade.sh" => "millennium-upgrade"
    bin.install "scripts/millennium-schedule.sh" => "millennium-schedule"
    bin.install "scripts/millennium-purge.sh" => "millennium-purge"
    bin.install "scripts/millennium-diag.sh" => "millennium-diag"
    bin.install "scripts/millennium-theme.sh" => "millennium-theme"
    bin.install "scripts/millennium-mcp.py" => "millennium-mcp"
    bin.install "scripts/millennium.sh" => "millennium"

    # Install shared library
    (lib/"millennium-helpers").install "scripts/common.sh"
    (lib/"millennium-helpers/lib").install Dir["scripts/lib/*.sh"]

    # Install completions (base + per-command symlinks for bash-completion v2 / zsh)
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

    # Install man pages
    man1.install Dir["man/*.1"]

    # Install VERSION for --version lookups
    (lib/"millennium-helpers").install "VERSION"
  end

  def caveats
    <<~EOS
      To enable daily automated updates on macOS, run:
        millennium-schedule enable

      Nushell completions are installed to:
        #{opt_share}/nushell/completions/millennium-helpers.nu
      Source or add that path from your Nushell config if needed.
    EOS
  end

  test do
    system "#{bin}/millennium-diag", "--help"
    assert_path_exists lib/"millennium-helpers/common.sh"
    assert_path_exists bash_completion/"millennium"
    assert_path_exists zsh_completion/"_millennium"
  end
end
