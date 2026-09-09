cask "omasend" do
  version "0.2.1"
  sha256 "4d33920a218cacd1b34d8d1f819ba5857cb0d302a3edc44e6c9941ecdb2c3056"

  url "https://github.com/Aayush9029/OmaSend/releases/download/macos-v#{version}/OmaSend_#{version}_macOS_arm64.zip"
  name "OmaSend"
  desc "Encrypted clipboard sharing across your computers"
  homepage "https://github.com/Aayush9029/OmaSend"

  depends_on arch: :arm64
  depends_on macos: ">= :sequoia"

  app "OmaSend.app"
end
