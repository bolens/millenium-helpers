class MillenniumHelpers < Formula
  desc "Go CLI and helpers for managing Millennium Steam mods"
  homepage "https://github.com/bolens/millenium-helpers"
  url "https://github.com/bolens/millenium-helpers/releases/download/v2.7.0/millennium-helpers-v2.7.0-src.tar.gz"
  sha256 "51266f867a227d1c7122b9221fa76c5d926d9686924349484676bddb7535182d"
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
    %w[
      millennium-mcp
      millennium-repair
      millennium-upgrade
      millennium-schedule
      millennium-purge
      millennium-diag
      millennium-theme
    ].each { |name| bin.install_symlink "millennium" => name }

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
      To enable daily automated updates on macOS, run:
        millennium schedule enable

      For the prebuilt release-asset formula, see: millennium-helpers-bin

      Nushell completions are installed to:
        #{opt_share}/nushell/completions/millennium-helpers.nu
    EOS
  end

  test do
    system "#{bin}/millennium", "version"
    system "#{bin}/millennium-diag", "--help"
    assert_path_exists lib/"millennium-helpers/VERSION"
    assert_path_exists bash_completion/"millennium"
  end
end
