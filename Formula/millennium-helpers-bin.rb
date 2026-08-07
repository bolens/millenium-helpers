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
      url "https://github.com/bolens/millenium-helpers/releases/download/v3.2.0/millennium-helpers-v3.2.0-darwin-arm64.tar.gz"
      sha256 "b4c95eb2bedba6586c894ab8ff61d8781800b3cbdfb31f486b1000ce001da540"
    end
    on_intel do
      url "https://github.com/bolens/millenium-helpers/releases/download/v3.2.0/millennium-helpers-v3.2.0-darwin-amd64.tar.gz"
      sha256 "18d2baddccfb1d5178e3c0f6262c74d0af23bf53d30e58ed2f577f0722c2de4f"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/bolens/millenium-helpers/releases/download/v3.2.0/millennium-helpers-v3.2.0-linux-arm64.tar.gz"
      sha256 "2272bab6020b6d607855d565238c159be1f8bcc195a7b608ab77a73161de9d08"
    end
    on_intel do
      url "https://github.com/bolens/millenium-helpers/releases/download/v3.2.0/millennium-helpers-v3.2.0-linux-amd64.tar.gz"
      sha256 "2819ddad943238421e7bffb1585950b6fe322fc88e874d19a460496540661d2f"
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
