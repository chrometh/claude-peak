class ClaudePeak < Formula
  desc "Claude Max subscription usage monitor for macOS menu bar"
  homepage "https://github.com/letsur-dev/claude-peak"
  url "https://github.com/letsur-dev/claude-peak/archive/refs/tags/v1.3.0.tar.gz"
  sha256 "e5fd4be1bfa102559a256547ba49ca19847be5e8a382c5d1ecab14c2c5a9fa88"
  license "MIT"

  bottle do
    root_url "https://github.com/letsur-dev/claude-peak/releases/download/v1.3.0"
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "bd3dba949b6a59e05e710deb3d8c8a42cbc1628c1486f790833935c0a070c882"
    sha256 cellar: :any_skip_relocation, arm64_tahoe: "001e4c337ae3e881688c1b0519d8ec644cfa3875648f0a5e92dd1eaf5bd693de"
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
