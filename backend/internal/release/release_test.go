package release

import "testing"

func TestURL(t *testing.T) {
	t.Parallel()
	for tag, want := range map[string]string{
		"v1.0":        "B/v1.0/SHA256SUMS",
		"edge":        "B/edge/SHA256SUMS",
		"":            "",
		"v1/../other": "",
		"..":          "",
		"v1?x":        "",
	} {
		if got, _ := URL("B", tag, Sums); got != want {
			t.Errorf("URL(%q) = %q, want %q", tag, got, want)
		}
	}
}

func TestAsset(t *testing.T) {
	t.Parallel()
	if asset, ok := Asset("arm64"); !ok || asset != "axiom-linux-arm64" {
		t.Errorf("arm64: %q", asset)
	}
	if _, ok := Asset("riscv64"); ok {
		t.Error("riscv64 has a release binary")
	}
}

func TestSumFor(t *testing.T) {
	t.Parallel()
	sums := "aaa  axiom-linux-amd64\nbbb *axiom-linux-arm64\nccc  axiom-linux-amd64.sig\n"
	for name, want := range map[string]string{"axiom-linux-amd64": "aaa", "axiom-linux-arm64": "bbb", "axiom": ""} {
		if got := SumFor(sums, name); got != want {
			t.Errorf("SumFor(%q) = %q, want %q", name, got, want)
		}
	}
}

func TestParseCommit(t *testing.T) {
	t.Parallel()
	full := "0123456789abcdef0123456789abcdef01234567"
	for _, tc := range []struct {
		data, want string
		ok         bool
	}{
		{full + "\n", full, true},
		{full, full, true},
		{full + "\n\n", "", false},
		{full[:39] + "\n", "", false},
		{"0123456789ABCDEF0123456789abcdef01234567\n", "", false},
		{"", "", false},
	} {
		if got, ok := ParseCommit(tc.data); got != tc.want || ok != tc.ok {
			t.Errorf("ParseCommit(%q) = %q, %v; want %q, %v", tc.data, got, ok, tc.want, tc.ok)
		}
	}
}
