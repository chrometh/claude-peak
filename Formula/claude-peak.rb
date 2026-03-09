class ClaudePeak < Formula
  desc "Claude Max subscription usage monitor for macOS menu bar"
  homepage "https://github.com/letsur-dev/claude-peak"
  url "https://github.com/letsur-dev/claude-peak/archive/refs/tags/v1.3.1.tar.gz"
  sha256 "ca22d338e1709d2cf2d9611da5809e5a7fa58fa735a7c5d5046b0a25f4c7d5a4"
  license "MIT"

  bottle do
    root_url "https://github.com/letsur-dev/claude-peak/releases/download/v1.3.1"
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "7d015feea39dba456a3c1c2697ca0184fd086bf67aac8fcd0af2886b745b1170"
    sha256 cellar: :any_skip_relocation, arm64_tahoe: "e8a46284c5d3d36cf79e7a093c05b1016bc9fe9b2df15c3905b65a481b9ef831"
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
