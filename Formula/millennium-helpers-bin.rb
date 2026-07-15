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
      url "https://github.com/bolens/millenium-helpers/releases/download/v2.6.2/millennium-helpers-v2.6.2-darwin-arm64.tar.gz"
      sha256 "c077c3f536e751e776fabb329600b18d7452d455a2e2dd1908491332569f4e55"
    end
    on_intel do
      url "https://github.com/bolens/millenium-helpers/releases/download/v2.6.2/millennium-helpers-v2.6.2-darwin-amd64.tar.gz"
      sha256 "c077c3f536e751e776fabb329600b18d7452d455a2e2dd1908491332569f4e55"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/bolens/millenium-helpers/releases/download/v2.6.2/millennium-helpers-v2.6.2-linux-arm64.tar.gz"
      sha256 "c077c3f536e751e776fabb329600b18d7452d455a2e2dd1908491332569f4e55"
    end
    on_intel do
      url "https://github.com/bolens/millenium-helpers/releases/download/v2.6.2/millennium-helpers-v2.6.2-linux-amd64.tar.gz"
      sha256 "c077c3f536e751e776fabb329600b18d7452d455a2e2dd1908491332569f4e55"
    end
  end

  conflicts_with "millennium-helpers", because: "both install the millennium helper tools"

  def install
    odie "Release archive missing bin/millennium (Go dispatcher required)" unless (buildpath/"bin/millennium").exist?
    bin.install "bin/millennium"
    %w[
      millennium-mcp
      millennium-repair
      millennium-upgrade
      millennium-schedule
      millennium-purge
      millennium-diag
      millennium-theme
    ].each { |name| bin.install_symlink "millennium" => name }

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
      This formula installs the published OS/arch release tarball.
      For a from-source build with `go`, use: millennium-helpers
    EOS
  end

  test do
    system "#{bin}/millennium-diag", "--help"
    assert_path_exists lib/"millennium-helpers/common.sh"
  end
end
