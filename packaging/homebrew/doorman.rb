# Template for schowave/homebrew-tap/Formula/doorman.rb.
# The release workflow fills in VERSION and SHA256 and pushes it to the tap.
class Doorman < Formula
  desc "Pick the browser, Chrome profile or Zen workspace for every link you open"
  homepage "https://github.com/schowave/doorman"
  url "https://github.com/schowave/doorman/archive/refs/tags/vVERSION.tar.gz"
  sha256 "SHA256"
  license "MIT"
  head "https://github.com/schowave/doorman.git", branch: "main"

  depends_on macos: :sonoma

  def install
    # Homebrew's sandbox forbids SwiftPM's own sandbox.
    system "make", "install",
           "PREFIX=#{prefix}",
           "VERSION=#{version}",
           "SWIFT_BUILD_FLAGS=--disable-sandbox"
  end

  def caveats
    <<~EOS
      Start Doorman once; it then offers to become your default browser
      and adds itself as a login item:
        open #{opt_prefix}/Doorman.app

      After `brew upgrade doorman`, quit Doorman from the menu bar and start it again.
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
