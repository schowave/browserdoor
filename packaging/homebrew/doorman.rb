# Template for schowave/homebrew-tap/Formula/doorman.rb.
# The release workflow (`mise run render-formula`) replaces the @…@ placeholders.
class Doorman < Formula
  desc "Pick the browser, Chrome profile or Zen workspace for every link you open"
  homepage "https://github.com/schowave/doorman"
  url "https://github.com/schowave/doorman/archive/refs/tags/v@VERSION@.tar.gz"
  sha256 "@SHA256@"
  license "MIT"
  head "https://github.com/schowave/doorman.git", branch: "main"

  depends_on macos: :sonoma

  # Needs a Swift 6 toolchain (Xcode 16 or its Command Line Tools).

  def install
    # The repo's mise task is a plain shell script; no mise needed here.
    ENV["PREFIX"] = prefix.to_s
    ENV["VERSION"] = version.to_s
    # Homebrew's sandbox forbids SwiftPM's own sandbox.
    ENV["SWIFT_BUILD_FLAGS"] = "--disable-sandbox"
    system ".mise/tasks/install"
  end

  def caveats
    <<~EOS
      Start Doorman once; it then offers to become your default browser,
      links itself to ~/Applications/Doorman.app and adds a login item:
        open #{opt_prefix}/Doorman.app

      After `brew upgrade doorman`, quit Doorman from the menu bar and run
        open ~/Applications/Doorman.app
      Configuration: ~/.config/doorman/config.json (menu bar → Konfiguration öffnen…)
    EOS
  end

  test do
    assert_path_exists prefix/"Doorman.app/Contents/MacOS/Doorman"
    assert_equal "io.github.schowave.doorman",
                 shell_output("/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' " \
                              "#{prefix}/Doorman.app/Contents/Info.plist").strip
  end
end
