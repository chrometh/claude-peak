class ClaudePeak < Formula
  desc "Claude Max subscription usage monitor for macOS menu bar"
  homepage "https://github.com/letsur-dev/claude-peak"
  url "https://github.com/letsur-dev/claude-peak/archive/refs/tags/v1.3.0.tar.gz"
  sha256 "e5fd4be1bfa102559a256547ba49ca19847be5e8a382c5d1ecab14c2c5a9fa88"
  license "MIT"

  bottle do
    root_url "https://github.com/letsur-dev/claude-peak/releases/download/v1.3.0"
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "c647c2988092140f8174f83e7d1720aabbbecccefa4720b0fce8c49bb84f7d37"
    sha256 cellar: :any_skip_relocation, arm64_tahoe: "f4e83877a2f7d20b00bd183e24deff40b33ba541118ef015dda956398b86d689"
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
