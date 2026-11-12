package integrations

import (
	"strings"
	"testing"
)

func str(s string) *string { return &s }

func TestRestoreKeysOfAGoneKeyWithNoPriorIsRestored(t *testing.T) {
	t.Parallel()
	prior := Keys{Groups: map[string]map[string]*string{"G": {"a": nil, "b": str("1")}}}
	wrote := Keys{Groups: map[string]map[string]*string{"G": {"a": str("x"), "b": str("2")}}}
	// The user removed "a" (axiom's, nothing before it) and changed "b"
	text := []byte("[G]\nb=3\n")
	out, changed := RestoreKeys(text, prior, wrote)
	if strings.Join(changed, ",") != "G/b" {
		t.Errorf("changed %v", changed)
	}
	if string(out) != string(text) {
		t.Errorf("%q", out)
	}
	if got := KeysAre(text, wrote, prior); strings.Join(got, ",") != "G/b" {
		t.Errorf("KeysAre %v", got)
	}
	// A gone key that had a value before is changed
	if got := KeysAre([]byte("[G]\n"), wrote, prior); strings.Join(got, ",") != "G/b" {
		t.Errorf("KeysAre of a gone key %v", got)
	}
}

func TestRestoreKeysTakesARepeatedKeyOnce(t *testing.T) {
	t.Parallel()
	prior := Keys{Groups: map[string]map[string]*string{"G": {"a": nil}}}
	wrote := Keys{Groups: map[string]map[string]*string{"G": {"a": str("x")}}}
	out, _ := RestoreKeys([]byte("[G]\na=x\na=x\n"), prior, wrote)
	if string(out) != "[G]\na=x\n" {
		t.Errorf("%q", out)
	}
}

func TestMergeKDEKeepsTrailingBlankLines(t *testing.T) {
	t.Parallel()
	scheme := []byte("[Colors:View]\nBackgroundNormal=1,2,3\n")
	before := []byte("[General]\nColorScheme=Axiom\n\n\n")
	merged := MergeKDE(scheme, before)
	if !strings.HasPrefix(string(merged), "[General]\nColorScheme=Axiom\n\n\n") {
		t.Errorf("%q", merged)
	}
	// and an undo gives the file back as it was
	prior, wrote := KeysChanged(before, merged)
	if out, _ := RestoreKeys(merged, prior, wrote); string(out) != string(before) {
		t.Errorf("restored %q", out)
	}
	if got := MergeKDE(nil, []byte("[General]\nx=1\n\n")); string(got) != "[General]\nx=1\n\n" {
		t.Errorf("a file kept as it is: %q", got)
	}
}
