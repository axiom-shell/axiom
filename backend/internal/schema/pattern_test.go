package schema

import "testing"

// \s and \S match as JS's do (Unicode whitespace), in and out of classes;
// everything else is RE2 as written.
func TestCompilePatternReadsLikeJS(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		pattern, value string
		want           bool
	}{
		{`\S`, "\u00a0", false},
		{`\S`, " \u3000\ufeff\u2028", false},
		{`\S`, " a ", true},
		{`^\s+$`, "\u00a0\u2003\t", true},
		{`^\s+$`, "\u0085", false}, // NEL isn't whitespace in JS either
		{`^[\s,]+$`, ",\u00a0,", true},
		{`^[^\s]+$`, "a\u00a0b", false},
		{`^[^\s]+$`, "ab", true},
		{`^\\s$`, `\s`, true}, // an escaped backslash, then a plain s
		{`^[]a]+$`, "]a", true},
		{`^([01]?\d|2[0-3]):[0-5]\d$`, "23:59", true},
	} {
		re, err := CompilePattern(c.pattern)
		if err != nil {
			t.Errorf("%s: %v", c.pattern, err)
			continue
		}
		if got := re.MatchString(c.value); got != c.want {
			t.Errorf("%s on %q: %v, want %v", c.pattern, c.value, got, c.want)
		}
	}
	for _, p := range []string{`[\S]`, `[a\S]`, `(`} {
		if _, err := CompilePattern(p); err == nil {
			t.Errorf("%s compiled", p)
		}
	}
}
