cask "omasend" do
  version "0.2.0"
  sha256 "697b181d163657f050f1725a3b1066263b26f696f821fe5016b20e78dc82c502"

  url "https://github.com/Aayush9029/OmaSend/releases/download/v#{version}/OmaSend_#{version}_macOS_arm64.zip"
  name "OmaSend"
  desc "Encrypted clipboard sharing across your computers"
  homepage "https://github.com/Aayush9029/OmaSend"

  depends_on arch: :arm64
  depends_on macos: ">= :sequoia"

  app "OmaSend.app"
end
