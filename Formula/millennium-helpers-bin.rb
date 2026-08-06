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
      url "https://github.com/bolens/millenium-helpers/releases/download/v3.0.2/millennium-helpers-v3.0.2-darwin-arm64.tar.gz"
      sha256 "90f616c26bcfab132e1e4f64a4d48fec65405a36c662349b521dc2c25df79c68"
    end
    on_intel do
      url "https://github.com/bolens/millenium-helpers/releases/download/v3.0.2/millennium-helpers-v3.0.2-darwin-amd64.tar.gz"
      sha256 "c0aed97371be5cce0027eef2ebe54068a142f5bcd950dd5136cc41384a9af2d5"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/bolens/millenium-helpers/releases/download/v3.0.2/millennium-helpers-v3.0.2-linux-arm64.tar.gz"
      sha256 "7e277b2b94fa5adc369e417b5aaa40c269fc61d4d0d6b3d744c5d9b8282a596e"
    end
    on_intel do
      url "https://github.com/bolens/millenium-helpers/releases/download/v3.0.2/millennium-helpers-v3.0.2-linux-amd64.tar.gz"
      sha256 "bd2dc4a544c3f3f531b3ad04bf4bf487ff12153eef8dbac2f99b6b4ac402fa9d"
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
