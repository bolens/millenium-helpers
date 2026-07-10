class MillenniumHelpers < Formula
  desc "Cross-platform utilities and MCP server for Millennium Steam Client hook"
  homepage "https://github.com/bolens/millenium-helpers"
  url "https://github.com/bolens/millenium-helpers/releases/download/v2.2.1/millennium-helpers-linux.tar.gz"
  sha256 "b488e053f071863a174c4847095c0d76d7dea7d1316ef5ed54ca785476228b6b"
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

    # Install completions
    bash_completion.install "completions/bash/millennium-helpers" => "millennium-helpers"
    zsh_completion.install "completions/zsh/_millennium-helpers" => "_millennium-helpers"
    fish_completion.install Dir["completions/fish/*.fish"]

    # Install man pages
    man1.install Dir["man/*.1"]

    # Install VERSION for --version lookups
    (lib/"millennium-helpers").install "VERSION"
  end

  def caveats
    <<~EOS
      To enable daily automated updates on macOS, run:
        millennium-schedule enable
    EOS
  end

  test do
    system "#{bin}/millennium-diag", "--help"
  end
end
