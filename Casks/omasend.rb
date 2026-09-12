cask "omasend" do
  version "0.2.2"
  sha256 "3cfe5f27d49ea5ab7ea0652e6a80b88d8d8f523d69180a1c496579a517a3576d"

  url "https://github.com/Aayush9029/OmaSend/releases/download/macos-v#{version}/OmaSend_#{version}_macOS_arm64.zip"
  name "OmaSend"
  desc "Encrypted clipboard sharing across your computers"
  homepage "https://github.com/Aayush9029/OmaSend"

  depends_on arch: :arm64
  depends_on macos: ">= :sequoia"

  app "OmaSend.app"
end
