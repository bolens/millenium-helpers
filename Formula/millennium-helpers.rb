class MillenniumHelpers < Formula
  desc "Go CLI and helpers for managing Millennium Steam mods"
  homepage "https://github.com/bolens/millenium-helpers"
  url "https://github.com/bolens/millenium-helpers/releases/download/v3.0.1/millennium-helpers-v3.0.1-src.tar.gz"
  sha256 "3a332461e6e9ac7ac30457b92b5671d1e42c63c7a61be9d5e45bf847b31657d8"
  license "MIT"
  head "https://github.com/bolens/millenium-helpers.git", branch: "main"

  depends_on "go" => :build
  depends_on "bash"
  depends_on "curl"
  depends_on "jq"
  depends_on "python"
  depends_on "unzip"

  conflicts_with "millennium-helpers-bin", because: "both install the millennium helper tools"

  def install
    system "make", "build"

    odie "Go dispatcher bin/millennium missing after make build" unless (buildpath/"bin/millennium").exist?
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
      To enable daily automated updates on macOS, run:
        millennium schedule enable

      For the prebuilt release-asset formula, see: millennium-helpers-bin

      Nushell completions are installed to:
        #{opt_share}/nushell/completions/millennium-helpers.nu
    EOS
  end

  test do
    system "#{bin}/millennium", "version"
    system "#{bin}/millennium", "diag", "--help"
    assert_path_exists lib/"millennium-helpers/VERSION"
    assert_path_exists bash_completion/"millennium"
  end
end
