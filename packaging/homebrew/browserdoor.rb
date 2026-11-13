# Template for schowave/homebrew-tap/Formula/browserdoor.rb.
# The release workflow (`mise run render-formula`) replaces the @…@ placeholders and
# adds the `bottle do` block for the bottles it built (`mise run bottle`).
class Browserdoor < Formula
  desc "Pick the browser, Zen space, or Chrome or Firefox profile for every link"
  homepage "https://github.com/schowave/browserdoor"
  url "@URL@"
  sha256 "@SHA256@"
  license "MIT"
  head "https://github.com/schowave/browserdoor.git", branch: "main"

  # Only when building from source; bottles need no Xcode.
  depends_on xcode: ["16.0", :build] # Swift 6
  depends_on macos: :sonoma

  def install
    # The repo's mise task is a plain shell script; no mise needed here.
    ENV["PREFIX"] = prefix.to_s
    ENV["VERSION"] = version.to_s
    # Homebrew's sandbox forbids SwiftPM's own sandbox.
    ENV["SWIFT_BUILD_FLAGS"] = "--disable-sandbox"
    # bin/browserdoor should start the app via the stable opt path, not this Cellar version.
    ENV["BIN_APP_PATH"] = (opt_prefix/"Browserdoor.app").to_s
    system ".mise/tasks/install"
    # Up to 0.2.x the command was `doorman`; their update script restarts the app with it.
    bin.install_symlink "browserdoor" => "doorman"
  end

  def caveats
    <<~EOS
      Start Browserdoor once; it then offers to become your default browser,
      links itself to ~/Applications/Browserdoor.app and adds a login item:
        browserdoor

      Browserdoor restarts itself after `brew upgrade browserdoor`. Coming from 0.6.1 or
      earlier, quit it from the menu bar once and run `browserdoor` again.
      Configuration: ~/.config/browserdoor/config.json (menu bar → Konfiguration öffnen…)
    EOS
  end

  test do
    assert_path_exists prefix/"Browserdoor.app/Contents/MacOS/Browserdoor"
    assert_path_exists prefix/"Browserdoor.app/Contents/Resources/AppIcon.icns"
    # A bottle must not break the app's (ad-hoc) signature when Homebrew relocates it.
    system "codesign", "--verify", prefix/"Browserdoor.app"
    assert_match "open -a \"#{opt_prefix}/Browserdoor.app\"", (bin/"browserdoor").read
    assert_equal "browserdoor", (bin/"doorman").readlink.to_s
    assert_equal version.to_s,
                 shell_output("/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' " \
                              "#{prefix}/Browserdoor.app/Contents/Info.plist").strip
    assert_equal "io.github.schowave.browserdoor",
                 shell_output("/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' " \
                              "#{prefix}/Browserdoor.app/Contents/Info.plist").strip
  end
end
