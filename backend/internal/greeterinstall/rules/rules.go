// Package rules decides what the greeter's install takes and where from
// (package greeterinstall does it): a git remote as the https url root
// fetches, the channel's newest commit from `git ls-remote`'s answer,
// greetd's default_session lines, the .greeter-source line, what a copy
// ships and what a local copy's hash covers. Pure: the edge runs git,
// reads the files and writes.
package rules

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"
)

// The sources (Greeter.source, or "package" for a packaged axiom) and
// the git channels (SelfUpdate.channel).
const (
	SourceGit     = "git"
	SourceLocal   = "local"
	SourcePackage = "package"
	ChannelTags   = "tags"
	ChannelMain   = "main"
)

// Session is greetd's default_session command once installed: the
// installed copy's session script, by its real path.
const Session = "/usr/share/axiom-greeter/scripts/greeter/greeter-session.sh"

// PackagePath is the package source's code, and where the greeter finds it.
const PackagePath = "/usr/share/axiom"

// HTTPSURL is a remote's url as https, which root fetches without the
// user's keys: git@host:path and ssh://[user@]host/path; anything else as
// it is.
func HTTPSURL(remote string) string {
	if rest, ok := strings.CutPrefix(remote, "git@"); ok {
		if host, path, ok := strings.Cut(rest, ":"); ok {
			return "https://" + host + "/" + path
		}
	}
	if rest, ok := strings.CutPrefix(remote, "ssh://"); ok {
		if _, hostPath, ok := strings.Cut(rest, "@"); ok {
			rest = hostPath
		}
		return "https://" + rest
	}
	return remote
}

// Target is the commit a channel stands at on a remote.
type Target struct {
	Commit string
	Ref    string // refs/tags/<tag> or refs/heads/<branch>
}

// Name is the tag or branch.
func (t Target) Name() string {
	if name, ok := strings.CutPrefix(t.Ref, "refs/tags/"); ok {
		return name
	}
	return strings.TrimPrefix(t.Ref, "refs/heads/")
}

// Tag is the target's tag ("" for a branch).
func (t Target) Tag() string {
	if name, ok := strings.CutPrefix(t.Ref, "refs/tags/"); ok {
		return name
	}
	return ""
}

// Newest reads `git ls-remote`'s answer for the channel's newest commit:
// "tags" the newest v* tag in version order (an annotated tag by the
// commit it points at), "main" the main branch, else master. ok is false
// when the remote has none.
func Newest(refs, channel string) (t Target, ok bool) {
	plain, peeled := map[string]string{}, map[string]string{}
	var master string
	for line := range strings.Lines(refs) {
		commit, ref, found := strings.Cut(strings.TrimRight(line, "\r\n"), "\t")
		if !found {
			continue
		}
		switch {
		case channel == ChannelMain && ref == "refs/heads/main":
			return Target{Commit: commit, Ref: ref}, true
		case channel == ChannelMain && ref == "refs/heads/master":
			master = commit
		case channel != ChannelMain && strings.HasPrefix(ref, "refs/tags/v"):
			name := strings.TrimPrefix(ref, "refs/tags/")
			if base, ok := strings.CutSuffix(name, "^{}"); ok {
				peeled[base] = commit
			} else {
				plain[name] = commit
			}
		}
	}
	if channel == ChannelMain {
		return Target{Commit: master, Ref: "refs/heads/master"}, master != ""
	}
	newest := ""
	for name := range plain {
		if newest == "" || CompareVersions(name, newest) > 0 {
			newest = name
		}
	}
	if newest == "" {
		return Target{}, false
	}
	commit := plain[newest]
	if c, ok := peeled[newest]; ok {
		commit = c
	}
	return Target{Commit: commit, Ref: "refs/tags/" + newest}, true
}

// CompareVersions orders version strings as `sort -V` does: runs of
// digits by their number, the text between them byte by byte, "~" before
// anything.
func CompareVersions(a, b string) int {
	for a != "" || b != "" {
		var ta, tb string
		ta, a = cutRun(a, false)
		tb, b = cutRun(b, false)
		if c := compareText(ta, tb); c != 0 {
			return c
		}
		ta, a = cutRun(a, true)
		tb, b = cutRun(b, true)
		ta, tb = strings.TrimLeft(ta, "0"), strings.TrimLeft(tb, "0")
		if len(ta) != len(tb) {
			return sign(len(ta) - len(tb))
		}
		if c := strings.Compare(ta, tb); c != 0 {
			return c
		}
	}
	return 0
}

// cutRun splits s after its leading run of digits (or of non-digits).
func cutRun(s string, digits bool) (string, string) {
	i := 0
	for i < len(s) && (s[i] >= '0' && s[i] <= '9') == digits {
		i++
	}
	return s[:i], s[i:]
}

func compareText(a, b string) int {
	for i := 0; i < len(a) || i < len(b); i++ {
		if c := textOrder(a, i) - textOrder(b, i); c != 0 {
			return sign(c)
		}
	}
	return 0
}

// textOrder is a byte's weight in compareText: ~ first, then the end of
// the run, then letters, then everything else.
func textOrder(s string, i int) int {
	switch {
	case i >= len(s):
		return 0
	case s[i] == '~':
		return -1
	case s[i] >= 'a' && s[i] <= 'z' || s[i] >= 'A' && s[i] <= 'Z':
		return int(s[i])
	}
	return int(s[i]) + 256
}

func sign(n int) int {
	switch {
	case n < 0:
		return -1
	case n > 0:
		return 1
	}
	return 0
}

// GreetdValue is `key`'s value in greetd's [default_session] (command,
// user), unquoted; "" when it isn't set. The config is read line by line,
// as greetd's own example lays it out.
func GreetdValue(config, key string) string {
	section := ""
	for line := range strings.Lines(config) {
		if name, ok := sectionName(line); ok {
			section = name
			continue
		}
		if section != "default_session" {
			continue
		}
		if value, ok := keyValue(line, key); ok {
			return value
		}
	}
	return ""
}

// sectionName is a [section] line's name.
func sectionName(line string) (string, bool) {
	trimmed := strings.TrimSpace(line)
	if !strings.HasPrefix(trimmed, "[") {
		return "", false
	}
	return strings.Map(func(r rune) rune {
		if r == '[' || r == ']' || r == ' ' || r == '\t' {
			return -1
		}
		return r
	}, trimmed), true
}

// keyValue is a `key = value` line's value, its comment and quotes taken
// off.
func keyValue(line, key string) (string, bool) {
	name, value, ok := strings.Cut(line, "=")
	if !ok || strings.TrimSpace(name) != key {
		return "", false
	}
	value, _, _ = strings.Cut(value, "#")
	value = strings.TrimSpace(value)
	value = strings.TrimPrefix(value, `"`)
	value = strings.TrimSuffix(value, `"`)
	return value, true
}

// Origin is what an installed copy was made from: the first line of its
// .greeter-source ("git <channel> <url>" | "local" | "package <dir>").
type Origin struct {
	Source  string // SourceGit, SourceLocal, SourcePackage, or "" for none
	Channel string // git's
	URL     string // git's
	Dir     string // package's
}

// ParseOrigin reads a .greeter-source line.
func ParseOrigin(line string) Origin {
	line, _, _ = strings.Cut(line, "\n")
	kind, rest, _ := strings.Cut(line, " ")
	switch kind {
	case SourceLocal:
		return Origin{Source: SourceLocal}
	case SourcePackage:
		return Origin{Source: SourcePackage, Dir: rest}
	case SourceGit:
		channel, url, _ := strings.Cut(rest, " ")
		return Origin{Source: SourceGit, Channel: channel, URL: url}
	}
	return Origin{}
}

// String is the origin's .greeter-source line.
func (o Origin) String() string {
	switch o.Source {
	case SourceGit:
		return "git " + o.Channel + " " + o.URL
	case SourcePackage:
		return "package " + o.Dir
	}
	return o.Source
}

// Label is the origin as the status reports it: "git:tags" | "git:main"
// | "local" | "package" | "".
func (o Origin) Label() string {
	if o.Source == SourceGit {
		return "git:" + o.Channel
	}
	return o.Source
}

// Ships says whether a copy takes a file of axiom's tree (by its path
// from the tree's top): the greeter never runs the tests, docs, the
// binary's source (an install copies the built binary) or install.sh.
func Ships(path string) bool {
	return Hashes(path) && !strings.HasPrefix(path, "backend/")
}

// Hashes says whether a local copy's hash covers a file: what it ships,
// and the binary's source.
func Hashes(path string) bool {
	for _, dir := range []string{"tests/", ".github/", "docs/"} {
		if strings.HasPrefix(path, dir) {
			return false
		}
	}
	return path != "install.sh" && !strings.HasSuffix(path, ".md")
}

// FileSum is a file's SHA-256, by its path from the tree's top.
type FileSum struct {
	Path string
	Sum  [sha256.Size]byte
}

// LocalHash is a local copy's version: the hash of its files' hashes in
// `sha256sum`'s format, in the order git lists them, so it stays the
// hash the installer's script recorded.
func LocalHash(files []FileSum) string {
	h := sha256.New()
	for _, f := range files {
		fmt.Fprintf(h, "%s  %s\n", hex.EncodeToString(f.Sum[:]), f.Path)
	}
	return hex.EncodeToString(h.Sum(nil))
}

// The actions run as root.
const (
	ActionInstall   = "install"
	ActionUpdate    = "update"
	ActionUninstall = "uninstall"
)

// Request is one run of the installer as root, as its command line
// carries it: `<action> <repo> <user> [<staged> [<source> [<channel>
// [<binary>]]]]`. An update is run by the copy it replaces, so this argv
// is a contract between versions: a new argument only ever goes last.
type Request struct {
	Action string
	Repo   string // the user's axiom tree
	User   string // who the bundle's folder belongs to: pkexec's caller
	Staged string // the bundle just staged for the snapshot ("" for none)
	Source string // SourceGit (default), SourceLocal, SourcePackage
	// The git channel (default ChannelTags)
	Channel string
	// The binary the user's shell runs, which a local copy takes
	Binary string
}

// Args is the request's command line, less the program.
func (r Request) Args() []string {
	args := []string{r.Action, r.Repo, r.User}
	if r.Action == ActionUninstall {
		return args
	}
	return append(args, r.Staged, r.Source, r.Channel, r.Binary)
}

// ParseArgs reads a command line Args wrote (or an older version's
// shell did), filling in the defaults.
func ParseArgs(args []string) (Request, error) {
	arg := func(i int, fallback string) string {
		if i < len(args) && args[i] != "" {
			return args[i]
		}
		return fallback
	}
	r := Request{Action: arg(0, ""), Repo: arg(1, ""), User: arg(2, ""), Staged: arg(3, ""),
		Source: arg(4, SourceGit), Channel: arg(5, ChannelTags), Binary: arg(6, "")}
	switch r.Action {
	case ActionInstall, ActionUpdate, ActionUninstall:
	default:
		return r, fmt.Errorf("usage: greeter-install install|update <repo> <user> [<staged bundle> [<source> [<channel> [<binary>]]]] | uninstall <repo> <user>")
	}
	if r.Action == ActionUninstall {
		return r, nil
	}
	if r.Source != SourceGit && r.Source != SourceLocal && r.Source != SourcePackage {
		return r, fmt.Errorf("unknown source: %s", r.Source)
	}
	if r.Channel != ChannelTags && r.Channel != ChannelMain {
		return r, fmt.Errorf("unknown channel: %s", r.Channel)
	}
	return r, nil
}

// Result is what a run as root printed: one JSON object, the other half
// of the contract Request is.
type Result struct {
	OK      bool     `json:"ok"`
	Changed []string `json:"changed"`
	Backup  string   `json:"backup"`
	Error   string   `json:"error"`
}

// PointGreetd is greetd's config with default_session's command set to
// command, the rest kept line for line: the section's other lines and
// user stay, a section without a command gets one, and a config without
// the section gets it, with user "greeter" unless one is set.
func PointGreetd(config, command string) string {
	line := `command = "` + command + `"`
	userLine := ""
	if GreetdValue(config, "user") == "" {
		userLine = `user = "greeter"`
	}
	var out []string
	inSection, seen, done := false, false, false
	finish := func() {
		if inSection && !done {
			out, done = append(out, line), true
		}
		if inSection && userLine != "" {
			out, userLine = append(out, userLine), ""
		}
	}
	for text := range strings.Lines(config) {
		text = strings.TrimSuffix(text, "\n")
		if name, ok := sectionName(text); ok {
			finish()
			inSection = name == "default_session"
			seen = seen || inSection
			out = append(out, text)
			continue
		}
		if _, ok := keyValue(text, "command"); inSection && ok {
			if !done {
				out = append(out, line)
			}
			done = true
			continue
		}
		out = append(out, text)
	}
	finish()
	if !seen {
		if userLine == "" {
			userLine = `user = "greeter"`
		}
		out = append(out, "", "[default_session]", line, userLine)
	}
	return strings.Join(out, "\n") + "\n"
}

// ReleaseBase is where a GitHub repository's release assets download from
// (<base>/<tag>/<asset>); ok is false for a url that isn't one.
func ReleaseBase(url string) (string, bool) {
	path, ok := strings.CutPrefix(url, "https://github.com/")
	if !ok {
		return "", false
	}
	path = strings.TrimSuffix(strings.TrimSuffix(path, "/"), ".git")
	owner, repo, ok := strings.Cut(path, "/")
	if !ok || owner == "" || repo == "" || strings.Contains(repo, "/") {
		return "", false
	}
	return "https://github.com/" + path + "/releases/download", true
}

// ReleaseAsset is the release's prebuilt binary for an architecture (Go's
// GOARCH); ok is false for one releases don't build.
func ReleaseAsset(goarch string) (string, bool) {
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
