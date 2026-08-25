# Homebrew formula for ntree.
#
# Install from a tap (once this repo is pushed to github.com/c4d3j05/homebrew-tap
# or the main repo is tapped directly):
#
#   brew tap c4d3j05/ntree https://github.com/c4d3j05/ntree
#   brew install ntree
#
# Or install the tip of the default branch without a release:
#
#   brew install --HEAD c4d3j05/ntree/ntree
#
# When cutting a release, set `url` to the tagged tarball and fill in `sha256`
# with the output of:  brew fetch ntree  (or shasum -a 256 <tarball>).
class Ntree < Formula
  desc "Parallel git worktree workspaces with APFS copy-on-write"
  homepage "https://github.com/c4d3j05/ntree"
  license "MIT"
  version "0.1.0"

  # Stable release tarball. Update url + sha256 on each tagged release.
  url "https://github.com/c4d3j05/ntree/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  head "https://github.com/c4d3j05/ntree.git", branch: "main"

  depends_on "git"
  depends_on "jq"
  depends_on :macos # relies on APFS clonefile (cp -c) and diskutil

  def install
    bin.install "bin/ntree"
    bash_completion.install "completions/ntree.bash" => "ntree"
    pkgshare.install ".ntreerc.example"
  end

  test do
    assert_match "ntree #{version}", shell_output("#{bin}/ntree version")
    # doctor should run; it exits non-zero only on missing deps, so just
    # confirm it reports on the filesystem check.
    (testpath/"repo").mkpath
    system "git", "-C", testpath/"repo", "init"
    output = shell_output("cd #{testpath}/repo && #{bin}/ntree list")
    assert_match(/no workspaces/, output)
  end
end
