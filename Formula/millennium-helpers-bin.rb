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
      sha256 "f437e494dc630f0f739a91fad1bbe083df20b403efe7254af876c8e31075b26c"
    end
    on_intel do
      url "https://github.com/bolens/millenium-helpers/releases/download/v3.0.1/millennium-helpers-v3.0.1-darwin-amd64.tar.gz"
      sha256 "4cbc14dcebed11c80d607e3ee9ad49be93ccfba0e41af3651764d3ad0300a26d"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/bolens/millenium-helpers/releases/download/v3.0.1/millennium-helpers-v3.0.1-linux-arm64.tar.gz"
      sha256 "9b35d5eccb0adfe43dd01d9b0d5247454b4d71bb81862931c2d57bab481af440"
    end
    on_intel do
      url "https://github.com/bolens/millenium-helpers/releases/download/v3.0.1/millennium-helpers-v3.0.1-linux-amd64.tar.gz"
      sha256 "de7a0d7ae896dea26e982c45585b2117015e7224b90f754a5a2774578d1d3d92"
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
