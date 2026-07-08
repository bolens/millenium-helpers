class MillenniumHelpers < Formula
  desc "Cross-platform utility scripts for managing Millennium on Linux and macOS"
  homepage "https://github.com/bolens/millenium-helpers"
  url "https://github.com/bolens/millenium-helpers/archive/refs/tags/v0.1.0.tar.gz" # Placeholder URL, release-specific
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

    # Install shared library
    (lib/"millennium-helpers").install "scripts/common.sh"
    (lib/"millennium-helpers/lib").install Dir["scripts/lib/*.sh"]

    # Install completions
    bash_completion.install "completions/bash/millennium-helpers" => "millennium-helpers"
    zsh_completion.install "completions/zsh/_millennium-helpers" => "_millennium-helpers"
    fish_completion.install Dir["completions/fish/*.fish"]
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
