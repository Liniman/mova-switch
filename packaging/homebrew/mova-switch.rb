# Builds MovaSwitch from source for the tap liniman/tap. The keg holds the app; the
# mova-switch-install command puts it in ~/Applications with a stable local signature and a
# LaunchAgent, the same way install.sh does. A brew service is not used: Homebrew can only
# ad-hoc sign inside its sandbox, and macOS would drop the Accessibility grant on every upgrade.
class MovaSwitch < Formula
  desc "Fixes words typed in the wrong English or Ukrainian keyboard layout"
  homepage "https://github.com/Liniman/mova-switch"
  license "MIT"
  head "https://github.com/Liniman/mova-switch.git", branch: "main"

  depends_on "rust" => :build
  depends_on arch: :arm64
  depends_on macos: :ventura

  def install
    system "mac/build.sh", "--skip-tests"
    libexec.install "mac/.build/MovaSwitch.app"
    app = opt_libexec/"MovaSwitch.app"
    (bin/"mova-switch-install").write <<~SH
      #!/bin/sh
      exec /bin/sh "#{app}/Contents/Resources/install-app.sh" "#{app}"
    SH
    chmod 0755, bin/"mova-switch-install"
    bin.install "uninstall.sh" => "mova-switch-uninstall"
  end

  def caveats
    <<~EOS
      Finish the install, and again after every upgrade, with:
        mova-switch-install
      It copies MovaSwitch to ~/Applications and loads a LaunchAgent that starts it at login.
      Then turn on MovaSwitch in System Settings > Privacy & Security > Accessibility.
      Before `brew uninstall mova-switch`, run:
        mova-switch-uninstall
    EOS
  end

  test do
    assert_predicate libexec/"MovaSwitch.app/Contents/MacOS/MovaSwitch", :executable?
    assert_predicate libexec/"MovaSwitch.app/Contents/Resources/install-app.sh", :exist?
  end
end
