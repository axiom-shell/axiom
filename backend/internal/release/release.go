// Package release says where the official axiom binaries are published
// and how a download is checked: a v* tag's GitHub release, or the rolling
// edge prerelease rebuilt from every merge to main (.github/workflows/
// edge.yml), each with axiom-linux-<arch> files and a SHA256SUMS listing
// them; edge's also lists COMMIT, the commit it was built from. Pure: the
// edge package fetch downloads them.
package release

import (
	"strings"
)

// Official is where the official binaries are downloaded from
// (<Official>/<tag>/<file>): the official repository's releases, whatever
// remote a clone follows (maintainer, 2026-10-27: "pin official repo"), so
// the sums prove a binary is an official build.
const Official = "https://github.com/axiom-shell/axiom/releases/download"

// Edge is the rolling prerelease's tag: main's newest build. It isn't a
// v* tag, so nothing looking for releases takes it.
const Edge = "edge"

// The listing every release has, and the file naming edge's commit.
const (
	Sums   = "SHA256SUMS"
	Commit = "COMMIT"
)

// URL is a release file's url under base (<base>/<tag>/<file>); ok is
// false for a tag that would leave its release's folder.
func URL(base, tag, file string) (string, bool) {
	if tag == "" || strings.ContainsAny(tag, "/?#%\\") || strings.HasPrefix(tag, ".") {
		return "", false
	}
	return base + "/" + tag + "/" + file, true
}

// Asset is the prebuilt binary's file for an architecture (Go's GOARCH);
// ok is false for one the releases don't build.
func Asset(goarch string) (string, bool) {
	switch goarch {
	case "amd64", "arm64":
		return "axiom-linux-" + goarch, true
	}
	return "", false
}

// SumFor is a file's SHA-256 in a SHA256SUMS listing (`<hex>  <name>`, or
// `<hex> *<name>`), "" when it isn't listed.
func SumFor(sums, name string) string {
	for line := range strings.Lines(sums) {
		fields := strings.Fields(line)
		if len(fields) >= 2 && (fields[1] == name || fields[1] == "*"+name) {
			return fields[0]
		}
	}
	return ""
}

// ParseCommit is the full commit hash a COMMIT file names (40 lowercase
// hex digits and a newline); ok is false for anything else.
func ParseCommit(data string) (string, bool) {
	commit := strings.TrimSuffix(data, "\n")
	if len(commit) != 40 || strings.Trim(commit, "0123456789abcdef") != "" {
		return "", false
	}
	return commit, true
}
