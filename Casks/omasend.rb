cask "omasend" do
  version "0.2.1"
  sha256 "080d043aafc5406338c520ee7b372f15644ef498c8806c938126d302ee622df0"

  url "https://github.com/Aayush9029/OmaSend/releases/download/macos-v#{version}/OmaSend_#{version}_macOS_arm64.zip"
  name "OmaSend"
  desc "Encrypted clipboard sharing across your computers"
  homepage "https://github.com/Aayush9029/OmaSend"

  depends_on arch: :arm64
  depends_on macos: ">= :sequoia"

  app "OmaSend.app"
end
