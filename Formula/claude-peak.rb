class ClaudePeak < Formula
  desc "Claude Max subscription usage monitor for macOS menu bar"
  homepage "https://github.com/letsur-dev/claude-peak"
  url "https://github.com/letsur-dev/claude-peak/archive/refs/tags/v1.3.2.tar.gz"
  sha256 "285551f6df881a5f370a43946c94e4e2e714295d583a86c5bbafbfc9a9c780ef"
  license "MIT"

  bottle do
    root_url "https://github.com/letsur-dev/claude-peak/releases/download/v1.3.2"
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "d3faaa2e33033799b8ae8bb2579c7d47d5265288f992192c9917bfa3f8555e72"
    sha256 cellar: :any_skip_relocation, arm64_tahoe: "db232439a95879e984f07bc822212f3a6306829fdd50eb8aeda91087cdb8db16"
  end



  depends_on :macos

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"

    app_name = "Claude Peak"
    app_bundle = prefix/"#{app_name}.app"

    (app_bundle/"Contents/MacOS").mkpath
    (app_bundle/"Contents/Resources").mkpath
    cp buildpath/".build/release/ClaudePeak", app_bundle/"Contents/MacOS/ClaudePeak"
    cp buildpath/"Resources/Info.plist", app_bundle/"Contents/Info.plist"

    # Create a launcher script in bin/
    (bin/"claude-peak").write <<~EOS
      #!/bin/bash
      APP="#{app_bundle}"
      LINK="$HOME/Applications/Claude Peak.app"
      if [ ! -L "$LINK" ]; then
        mkdir -p "$HOME/Applications"
        rm -rf "$LINK"
        ln -sf "$APP" "$LINK"
      fi
      open "$APP"
    EOS
  end

  def caveats
    <<~EOS
      Run `claude-peak` to launch (auto-links to ~/Applications/ on first run).
      Or directly: open "#{prefix}/Claude Peak.app"

      First launch requires OAuth login via browser.
    EOS
  end
end
