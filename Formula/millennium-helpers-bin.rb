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
      url "https://github.com/bolens/millenium-helpers/releases/download/v3.0.1/millennium-helpers-v3.0.1-darwin-arm64.tar.gz"
      sha256 "e005028f78d78e1fd437bf049b07048d5c530c0b2fd04161f972857966401a64"
    end
    on_intel do
      url "https://github.com/bolens/millenium-helpers/releases/download/v3.0.1/millennium-helpers-v3.0.1-darwin-amd64.tar.gz"
      sha256 "03a2cfdab469d9e0bd60b62f34e2adae1985ac4301eb0969d39bf8e5cdbaf2b4"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/bolens/millenium-helpers/releases/download/v3.0.1/millennium-helpers-v3.0.1-linux-arm64.tar.gz"
      sha256 "ee89e8cf39839cd631c14316b4a3e34b89309bcb61ef8944b73e56ecd9d9ae87"
    end
    on_intel do
      url "https://github.com/bolens/millenium-helpers/releases/download/v3.0.1/millennium-helpers-v3.0.1-linux-amd64.tar.gz"
      sha256 "5ec3c429c16f4096cb0fb66a561b9fd8f44e8a8fd0d4e4de7cc6ec9a58a53f0c"
    end
  end

  conflicts_with "millennium-helpers", because: "both install the millennium helper tools"

  def install
    odie "Release archive missing bin/millennium (Go dispatcher required)" unless (buildpath/"bin/millennium").exist?
    bin.install "bin/millennium"
    bash_completion.install "completions/bash/millennium-helpers" => "millennium-helpers"
    ln_sf "millennium-helpers", bash_completion/"millennium"

    zsh_completion.install "completions/zsh/_millennium-helpers" => "_millennium-helpers"
    ln_sf "_millennium-helpers", zsh_completion/"_millennium"

    fish_completion.install "completions/fish/millennium.fish"
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
