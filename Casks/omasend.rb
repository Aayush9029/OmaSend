cask "omasend" do
  version "0.1.3"
  sha256 "659778fd0fefc7ae4c023058766ef851c155ff8d4b04a8562ecbb3a04ed24afc"

  url "https://github.com/Aayush9029/OmaSend/releases/download/v#{version}/OmaSend_#{version}_macOS_arm64.zip"
  name "OmaSend"
  desc "Encrypted clipboard sharing across your computers"
  homepage "https://github.com/Aayush9029/OmaSend"

  depends_on arch: :arm64
  depends_on macos: ">= :sequoia"

  app "OmaSend.app"
end
