class ScipSwift < Formula
  desc "SCIP indexer for Swift — converts IndexStoreDB data to scip.proto"
  homepage "https://github.com/jarvis-intelligence/scip-swift"
  url "https://github.com/jarvis-intelligence/scip-swift/releases/download/v0.2.0/scip-swift-0.2.0.tar.gz"
  sha256 "8c30573b1d9249b2b91e9c7cac0232967e12a20e6e14514df68613dd46749007"
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
