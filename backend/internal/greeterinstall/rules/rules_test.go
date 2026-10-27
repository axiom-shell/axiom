package rules

import (
	"crypto/sha256"
	"encoding/hex"
	"os/exec"
	"slices"
	"strings"
	"testing"
)

func TestNewest(t *testing.T) {
	t.Parallel()
	refs := strings.Join([]string{
		"aaa\tHEAD",
		"bbb\trefs/heads/master",
		"ccc\trefs/heads/main",
		"d04\trefs/tags/other",
		"d03\trefs/tags/v1.10^{}",
		"d02\trefs/tags/v1.10",
		"d01\trefs/tags/v1.9",
		"d05\trefs/tags/v1.2",
	}, "\n") + "\n"
	for _, tc := range []struct {
		name, refs, channel string
		want                Target
		ok                  bool
	}{
		{"tags, by version, peeled", refs, ChannelTags, Target{"d03", "refs/tags/v1.10"}, true},
		{"main", refs, ChannelMain, Target{"ccc", "refs/heads/main"}, true},
		{"master without main", "bbb\trefs/heads/master\n", ChannelMain, Target{"bbb", "refs/heads/master"}, true},
		{"a lightweight tag", "e01\trefs/tags/v2.0\n", ChannelTags, Target{"e01", "refs/tags/v2.0"}, true},
		{"no releases", "ccc\trefs/heads/main\n", ChannelTags, Target{}, false},
		{"no main", "", ChannelMain, Target{Ref: "refs/heads/master"}, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got, ok := Newest(tc.refs, tc.channel)
			if ok != tc.ok || (ok && got != tc.want) {
				t.Errorf("Newest = %+v, %v; want %+v, %v", got, ok, tc.want, tc.ok)
			}
		})
	}
	if target := (Target{Ref: "refs/tags/v1.0"}); target.Name() != "v1.0" || target.Tag() != "v1.0" {
		t.Errorf("tag target: %q %q", target.Name(), target.Tag())
	}
	if target := (Target{Ref: "refs/heads/main"}); target.Name() != "main" || target.Tag() != "" {
		t.Errorf("branch target: %q %q", target.Name(), target.Tag())
	}
}

func TestGreetdValue(t *testing.T) {
	t.Parallel()
	config := `[terminal]
vt = 1
command = "not this one"

[ default_session ]
# the greeter
command = "agreety --cmd /bin/sh"   # a comment
  user="greeter"
`
	for key, want := range map[string]string{"command": "agreety --cmd /bin/sh", "user": "greeter", "vt": ""} {
		if got := GreetdValue(config, key); got != want {
			t.Errorf("GreetdValue(%q) = %q, want %q", key, got, want)
		}
	}
	if GreetdValue("", "command") != "" {
		t.Error("an empty config has a command")
	}
}

func TestOrigin(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		line  string
		want  Origin
		label string
	}{
		{"git tags https://github.com/a/b\n", Origin{Source: SourceGit, Channel: "tags", URL: "https://github.com/a/b"}, "git:tags"},
		{"git main /x/upstream.git", Origin{Source: SourceGit, Channel: "main", URL: "/x/upstream.git"}, "git:main"},
		{"local\n", Origin{Source: SourceLocal}, "local"},
		{"package /usr/share/axiom\n", Origin{Source: SourcePackage, Dir: "/usr/share/axiom"}, "package"},
		{"", Origin{}, ""},
		{"svn x", Origin{}, ""},
	} {
		got := ParseOrigin(tc.line)
		if got != tc.want || got.Label() != tc.label {
			t.Errorf("ParseOrigin(%q) = %+v (%q)", tc.line, got, got.Label())
		}
		if tc.want.Source != "" && got.String() != strings.TrimSuffix(tc.line, "\n") {
			t.Errorf("%+v.String() = %q", got, got.String())
		}
	}
}

func TestShipsAndHashes(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		path          string
		ships, hashes bool
	}{
		{"greeter.qml", true, true},
		{"scripts/greeter/greeter-session.sh", true, true},
		{"backend/go.mod", false, true},
		{"tests/tst_x.qml", false, false},
		{"docs/notes.md", false, false},
		{".github/workflows/ci.yml", false, false},
		{"install.sh", false, false},
		{"scripts/install.sh", true, true},
		{"components/AGENTS.md", false, false},
		{"components/tests/x.qml", true, true},
	} {
		if Ships(tc.path) != tc.ships || Hashes(tc.path) != tc.hashes {
			t.Errorf("%s: ships %v hashes %v", tc.path, Ships(tc.path), Hashes(tc.path))
		}
	}
}

// LocalHash is what the script's `sha256sum | sha256sum` made, so a local
// copy it installed isn't taken for an outdated one.
func TestLocalHashIsSha256sums(t *testing.T) {
	t.Parallel()
	if _, err := exec.LookPath("sha256sum"); err != nil {
		t.Skip("no sha256sum")
	}
	files := []FileSum{{"a.qml", sha256.Sum256([]byte("a"))}, {"dir/b.sh", sha256.Sum256([]byte("b"))}}
	var listing strings.Builder
	for _, f := range files {
		listing.WriteString(hex.EncodeToString(f.Sum[:]) + "  " + f.Path + "\n")
	}
	cmd := exec.Command("sha256sum")
	cmd.Stdin = strings.NewReader(listing.String())
	out, err := cmd.Output()
	if err != nil {
		t.Fatal(err)
	}
	if want, _, _ := strings.Cut(string(out), " "); LocalHash(files) != want {
		t.Errorf("LocalHash = %s, want %s", LocalHash(files), want)
	}
}

func TestArgs(t *testing.T) {
	t.Parallel()
	install := Request{Action: ActionInstall, Repo: "/r", User: "me", Source: SourceLocal, Channel: ChannelTags, Binary: "/b"}
	if got := install.Args(); !slices.Equal(got, []string{"install", "/r", "me", "", "local", "tags", "/b"}) {
		t.Errorf("Args = %q", got)
	}
	if got, err := ParseArgs(install.Args()); err != nil || got != install {
		t.Errorf("ParseArgs(Args) = %+v, %v", got, err)
	}
	uninstall := Request{Action: ActionUninstall, Repo: "/r", User: "me"}
	if got := uninstall.Args(); !slices.Equal(got, []string{"uninstall", "/r", "me"}) {
		t.Errorf("Args = %q", got)
	}
	// An older shell's short command line takes the defaults
	if got, err := ParseArgs([]string{"update", "/r", "me"}); err != nil || got.Source != SourceGit || got.Channel != ChannelTags {
		t.Errorf("defaults: %+v, %v", got, err)
	}
	for args, want := range map[string]string{
		"bogus":                   "usage",
		"install /r me  svn":      "unknown source",
		"install /r me  git beta": "unknown channel",
	} {
		if _, err := ParseArgs(strings.Split(args, " ")); err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("ParseArgs(%q): %v, want %q", args, err, want)
		}
	}
}

func TestPointGreetd(t *testing.T) {
	t.Parallel()
	const cmd = `command = "` + Session + `"`
	for _, tc := range []struct{ name, config, want string }{
		{"replaces the command, keeps the rest",
			"[terminal]\nvt = 1\n\n[default_session]\n# the greeter\ncommand = \"agreety --cmd /bin/sh\"\nuser = \"me\"\n",
			"[terminal]\nvt = 1\n\n[default_session]\n# the greeter\n" + cmd + "\nuser = \"me\"\n"},
		{"a section without a command gets one",
			"[default_session]\nuser = \"me\"\n\n[terminal]\nvt = 1\n",
			"[default_session]\nuser = \"me\"\n\n" + cmd + "\n[terminal]\nvt = 1\n"},
		{"a section without a user gets greeter",
			"[default_session]\ncommand = \"x\"\n",
			"[default_session]\n" + cmd + "\nuser = \"greeter\"\n"},
		{"no section",
			"[terminal]\nvt = 1\n",
			"[terminal]\nvt = 1\n\n[default_session]\n" + cmd + "\nuser = \"greeter\"\n"},
		{"two commands keep one",
			"[default_session]\ncommand = \"a\"\ncommand = \"b\"\nuser = \"me\"\n",
			"[default_session]\n" + cmd + "\nuser = \"me\"\n"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got := PointGreetd(tc.config, Session)
			if got != tc.want {
				t.Errorf("got\n%s\nwant\n%s", got, tc.want)
			}
			if GreetdValue(got, "command") != Session {
				t.Error("doesn't read back")
			}
		})
	}
}
