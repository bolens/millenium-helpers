class MillenniumHelpersBin < Formula
  desc "Prebuilt CLI and helpers for managing Millennium Steam mods"
  homepage "https://github.com/bolens/millenium-helpers"
  license "MIT"

  depends_on "bash"
  depends_on "curl"
  depends_on "jq"
  depends_on "python"
  depends_on "unzip"

  on_macos do
    on_arm do
      url "https://github.com/bolens/millenium-helpers/releases/download/v2.7.0/millennium-helpers-v2.7.0-darwin-arm64.tar.gz"
      sha256 "bb3532ec10271709638cca737ae05cbe55673a508923c8a4d2f106e6bbae07c6"
    end
    on_intel do
      url "https://github.com/bolens/millenium-helpers/releases/download/v2.7.0/millennium-helpers-v2.7.0-darwin-amd64.tar.gz"
      sha256 "10a75d831d9648c487a5cc303e615902a9565f9e1689403fc5dd4a9ba90db6e6"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/bolens/millenium-helpers/releases/download/v2.7.0/millennium-helpers-v2.7.0-linux-arm64.tar.gz"
      sha256 "5067b7592df4c06b20406c0e8da50cad76c541c401c4b6d6df8cee6d90833535"
    end
    on_intel do
      url "https://github.com/bolens/millenium-helpers/releases/download/v2.7.0/millennium-helpers-v2.7.0-linux-amd64.tar.gz"
      sha256 "96baa9285be191a136aab460ba4e75edc426842333b7df8f719c8de724730ca1"
    end
  end

  conflicts_with "millennium-helpers", because: "both install the millennium helper tools"

  def install
    odie "Release archive missing bin/millennium (Go dispatcher required)" unless (buildpath/"bin/millennium").exist?
    bin.install "bin/millennium"
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
      This formula installs the published OS/arch release tarball.
      For a from-source build with `go`, use: millennium-helpers
    EOS
  end

  test do
    system "#{bin}/millennium", "diag", "--help"
    assert_path_exists lib/"millennium-helpers/VERSION"
  end
end
