class ScipSwift < Formula
  desc "SCIP indexer for Swift — converts IndexStoreDB data to scip.proto"
  homepage "https://github.com/phuongddx/scip-swift"
  url "https://github.com/phuongddx/scip-swift/releases/download/v0.2.0/scip-swift-0.2.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  version "0.2.0"
  license "Apache-2.0"
  depends_on macos: :sonoma

  def install
    bin.install "scip-swift"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/scip-swift --version")
  end
end
