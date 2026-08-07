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
      url "https://github.com/bolens/millenium-helpers/releases/download/v3.1.0/millennium-helpers-v3.1.0-darwin-arm64.tar.gz"
      sha256 "10de12883e7b69af056a0937bdc1dbd2723fe6f93d29a4fa39d0ce93aae36a31"
    end
    on_intel do
      url "https://github.com/bolens/millenium-helpers/releases/download/v3.1.0/millennium-helpers-v3.1.0-darwin-amd64.tar.gz"
      sha256 "25c944117bce660cadd4cf5304fbb82df613081b21af0ad13dc09cae40180470"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/bolens/millenium-helpers/releases/download/v3.1.0/millennium-helpers-v3.1.0-linux-arm64.tar.gz"
      sha256 "fcad2489126e8af827e510dd40a9e01f16325771e14ede7a1541ac5e9c187717"
    end
    on_intel do
      url "https://github.com/bolens/millenium-helpers/releases/download/v3.1.0/millennium-helpers-v3.1.0-linux-amd64.tar.gz"
      sha256 "ab0dbae309b6e750221beee8b4b05616bc535471b3268530fb90b7a174fe9b25"
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
