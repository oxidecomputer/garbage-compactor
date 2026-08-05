#!/bin/ksh
#:
#: name = "mfg-p5p"
#: variety = "basic"
#: target = "helios-3.0"
#: output_rules = [
#:   "/out/mfg.p5p",
#:   "/out/mfg.p5p.sha256",
#: ]
#:
#: [[publish]]
#: series = "repo"
#: name = "mfg.p5p"
#: from_output = "/out/mfg.p5p"
#:
#: [[publish]]
#: series = "repo"
#: name = "mfg.p5p.sha256"
#: from_output = "/out/mfg.p5p.sha256"
#:

set -ex

typeset -r PKG="mfg"
typeset -r PKG_NAME="/out/$PKG.p5p"

# For a push to master, look at the changes in the commit under test;
# for a PR branch, look at everything the branch changes relative to
# its merge base with master.
if [ "$GITHUB_BRANCH" = master ]; then
      BASE="HEAD~.."
else
      BASE="origin/master...HEAD"
fi

if git diff --name-only --exit-code "$BASE" -- "$PKG/"; then
      print "No changes to '$PKG'"
      exit 0
fi

pfexec mkdir -p /out
pfexec chown "$UID" /out

cd "$PKG"

banner build
./build.sh

banner publish
ls -lR work/
mv "work/"*.p5p "$PKG_NAME"
digest -a sha256 "$PKG_NAME" > "$PKG_NAME.sha256"

