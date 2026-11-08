# Template for schowave/homebrew-tap/Formula/doorman.rb.
# The release workflow (`mise run render-formula`) replaces the @…@ placeholders and
# adds the `bottle do` block for the bottles it built (`mise run bottle`).
class Doorman < Formula
  desc "Pick the browser, Chrome profile or Zen workspace for every link you open"
  homepage "https://github.com/schowave/doorman"
  url "@URL@"
  sha256 "@SHA256@"
  license "MIT"
  head "https://github.com/schowave/doorman.git", branch: "main"

  # Only when building from source; bottles need no Xcode.
  depends_on xcode: ["16.0", :build] # Swift 6
  depends_on macos: :sonoma

  def install
    # The repo's mise task is a plain shell script; no mise needed here.
    ENV["PREFIX"] = prefix.to_s
    ENV["VERSION"] = version.to_s
    # Homebrew's sandbox forbids SwiftPM's own sandbox.
    ENV["SWIFT_BUILD_FLAGS"] = "--disable-sandbox"
    # bin/doorman should start the app via the stable opt path, not this Cellar version.
    ENV["BIN_APP_PATH"] = (opt_prefix/"Doorman.app").to_s
    system ".mise/tasks/install"
  end

  def caveats
    <<~EOS
      Start Doorman once; it then offers to become your default browser,
      links itself to ~/Applications/Doorman.app and adds a login item:
        doorman

      After `brew upgrade doorman`, quit Doorman from the menu bar and run `doorman` again.
      Configuration: ~/.config/doorman/config.json (menu bar → Konfiguration öffnen…)
    EOS
  end

  test do
    assert_path_exists prefix/"Doorman.app/Contents/MacOS/Doorman"
    assert_path_exists prefix/"Doorman.app/Contents/Resources/AppIcon.icns"
    # A bottle must not break the app's (ad-hoc) signature when Homebrew relocates it.
    system "codesign", "--verify", prefix/"Doorman.app"
    assert_match "open -a \"#{opt_prefix}/Doorman.app\"", (bin/"doorman").read
    assert_equal version.to_s,
                 shell_output("/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' " \
                              "#{prefix}/Doorman.app/Contents/Info.plist").strip
    assert_equal "io.github.schowave.doorman",
                 shell_output("/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' " \
                              "#{prefix}/Doorman.app/Contents/Info.plist").strip
  end
end
