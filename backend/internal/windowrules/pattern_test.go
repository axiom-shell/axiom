package windowrules

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

type patternRow struct {
	Op      Op       `json:"op"`
	Value   string   `json:"value"`
	Regex   string   `json:"regex"`
	Refused string   `json:"refused"`
	Invalid bool     `json:"invalid"`
	Matches []string `json:"matches"`
	Misses  []string `json:"misses"`
}

type negationRow struct {
	Values  []string `json:"values"`
	Regex   string   `json:"regex"`
	Matches []string `json:"matches"`
	Misses  []string `json:"misses"`
}

func checkMatches(t *testing.T, regex string, matches, misses []string) {
	t.Helper()
	re, err := regexp.Compile(regex)
	if err != nil {
		t.Errorf("%s doesn't compile: %v", regex, err)
		return
	}
	for _, s := range matches {
		if !re.MatchString(s) {
			t.Errorf("%s should match %q", regex, s)
		}
	}
	for _, s := range misses {
		if re.MatchString(s) {
			t.Errorf("%s should not match %q", regex, s)
		}
	}
}

func TestRegexFixture(t *testing.T) {
	t.Parallel()
	data, err := os.ReadFile(filepath.Join(testkit.RepoRoot(), "tests", "fixtures", "windowrules", "regex.json"))
	if err != nil {
		t.Fatal(err)
	}
	var fx struct {
		Patterns  []patternRow  `json:"patterns"`
		Negations []negationRow `json:"negations"`
	}
	if err := json.Unmarshal(data, &fx); err != nil {
		t.Fatal(err)
	}
	for _, row := range fx.Patterns {
		got, err := Condition{Field: FieldTitle, Op: row.Op, Value: row.Value}.Regex()
		var pe *PatternError
		switch {
		case row.Refused != "":
			if !errors.As(err, &pe) || pe.Code != "patternRefused" || pe.Arg != row.Refused {
				t.Errorf("%q: got %v, want refused %q", row.Value, err, row.Refused)
			}
		case row.Invalid:
			if !errors.As(err, &pe) || pe.Code != "patternInvalid" {
				t.Errorf("%q: got %v, want invalid", row.Value, err)
			}
		case err != nil:
			t.Errorf("%q: %v", row.Value, err)
		default:
			if got != row.Regex {
				t.Errorf("%q: got %s, want %s", row.Value, got, row.Regex)
			}
			checkMatches(t, got, row.Matches, row.Misses)
		}
	}
	for _, row := range fx.Negations {
		var k Kind
		for _, v := range row.Values {
			k.Conditions = append(k.Conditions, Condition{FieldTitle, OpIsNot, v})
		}
		l, err := Lower(k, nil)
		if err != nil || len(l.Tests) != 1 || !l.Tests[0].Negated || l.Tests[0].Regex != row.Regex {
			t.Errorf("%v: got %+v, %v, want one negated %s", row.Values, l, err, row.Regex)
			continue
		}
		checkMatches(t, row.Regex, row.Matches, row.Misses)
	}
}

func TestLiteralInvalidUTF8(t *testing.T) {
	t.Parallel()
	checkMatches(t, `\A(?:`+Literal("\xff")+`)\z`, []string{"\uFFFD"}, nil)
}
