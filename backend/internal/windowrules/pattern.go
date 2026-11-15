package windowrules

import (
	"errors"
	"regexp"
	"regexp/syntax"
	"strings"
)

// PatternError is why a pattern is refused: Code "patternInvalid" (Arg: Go's
// parse error without its "error parsing regexp: " prefix) or
// "patternRefused" (Arg: the construct, one of `(?m)`, `\Q…\E`, `\p`, `\b`).
type PatternError struct{ Code, Arg string }

func (e *PatternError) Error() string { return e.Code + ": " + e.Arg }

func refused(construct string) error {
	return &PatternError{Code: "patternRefused", Arg: construct}
}

// Normalise re-prints a user's pattern through regexp/syntax so every
// compositor's engine (RE2, Rust regex, PCRE2) reads it the same way.
func Normalise(pattern string) (string, error) {
	for i := 0; i+1 < len(pattern); {
		if pattern[i] != '\\' {
			i++
			continue
		}
		switch pattern[i+1] {
		case 'Q':
			return "", refused(`\Q…\E`)
		case 'p', 'P':
			return "", refused(`\p`)
		}
		i += 2
	}
	re, err := syntax.Parse(pattern, syntax.Perl)
	if err != nil {
		return "", &PatternError{Code: "patternInvalid", Arg: strings.TrimPrefix(err.Error(), "error parsing regexp: ")}
	}
	re, err = clean(re)
	if err != nil {
		return "", err
	}
	return vertical(re.String()), nil
}

// clean refuses what engines read differently and drops what would clash
// when patterns are joined: capture groups and names, and `$`'s PCRE2 meaning.
func clean(re *syntax.Regexp) (*syntax.Regexp, error) {
	switch re.Op {
	case syntax.OpBeginLine, syntax.OpEndLine:
		return nil, refused(`(?m)`)
	case syntax.OpWordBoundary, syntax.OpNoWordBoundary:
		return nil, refused(`\b`)
	case syntax.OpCapture:
		return clean(re.Sub[0])
	case syntax.OpEndText:
		re.Flags &^= syntax.WasDollar
	}
	for i, sub := range re.Sub {
		s, err := clean(sub)
		if err != nil {
			return nil, err
		}
		re.Sub[i] = s
	}
	return re, nil
}

// vertical rewrites each `\v` escape as `\x0b`: PCRE2 reads `\v` as any
// vertical space.
func vertical(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == '\\' && i+1 < len(s) {
			if s[i+1] == 'v' {
				b.WriteString(`\x0b`)
			} else {
				b.WriteString(s[i : i+2])
			}
			i++
			continue
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

// Literal is s as a normalised pattern matching exactly s.
func Literal(s string) string {
	p, err := Normalise(regexp.QuoteMeta(strings.ToValidUTF8(s, "\uFFFD")))
	if err != nil {
		panic("windowrules: a quoted literal was refused: " + err.Error())
	}
	return p
}

// Regex is the anchored pattern the condition's value becomes.
func (c Condition) Regex() (string, error) {
	switch c.Field {
	case FieldAppID, FieldTitle, FieldProcess, FieldStartedFrom:
		switch c.Op {
		case OpIs, OpIsNot:
			return `\A(?:` + Literal(c.Value) + `)\z`, nil
		case OpContains:
			return `\A(?s:.*)(?:` + Literal(c.Value) + `)(?s:.*)\z`, nil
		case OpMatches:
			p, err := Normalise(c.Value)
			if err != nil {
				return "", err
			}
			return `\A(?s:.*)(?:` + p + `)(?s:.*)\z`, nil
		}
	case FieldSteamGame:
		if c.Op == OpIs || c.Op == OpIsNot {
			return `\A(?:` + Literal("steam_app_"+c.Value) + `)\z`, nil
		}
	}
	return "", errors.New("windowrules: " + string(c.Field) + " " + string(c.Op) + " has no pattern")
}
