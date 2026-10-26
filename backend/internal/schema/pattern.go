package schema

import (
	"errors"
	"regexp"
	"strings"
)

// jsSpace is what JS's \s matches (ECMAScript WhiteSpace and
// LineTerminator): Go's RE2 \s is ASCII only, so U+00A0 alone would pass
// "\S" in Go and fail it in the shell.
const jsSpace = `\t\n\v\f\r\p{Zs}\x{2028}\x{2029}\x{feff}`

// CompilePattern compiles a schema `pattern` as JS reads it: RE2 syntax
// (a subset of JS's) with \s and \S widened to JS's Unicode whitespace. A
// \S inside a character class has no RE2 equivalent and is refused.
func CompilePattern(p string) (*regexp.Regexp, error) {
	translated, err := translatePattern(p)
	if err != nil {
		return nil, err
	}
	return regexp.Compile(translated)
}

func translatePattern(p string) (string, error) {
	var b strings.Builder
	inClass := false
	for i := 0; i < len(p); i++ {
		c := p[i]
		switch {
		case c == '\\' && i+1 < len(p):
			i++
			switch next := p[i]; {
			case next == 's' && inClass:
				b.WriteString(jsSpace)
			case next == 's':
				b.WriteString("[" + jsSpace + "]")
			case next == 'S' && inClass:
				return "", errors.New(`\S inside a character class can't be read as JS reads it: use [^\s…] or (?:…|\S)`)
			case next == 'S':
				b.WriteString("[^" + jsSpace + "]")
			default:
				b.WriteByte(c)
				b.WriteByte(next)
			}
		case c == '[' && !inClass:
			inClass = true
			b.WriteByte(c)
			if i+1 < len(p) && p[i+1] == '^' {
				i++
				b.WriteByte('^')
			}
			// A ] first in a class is a literal (RE2)
			if i+1 < len(p) && p[i+1] == ']' {
				i++
				b.WriteByte(']')
			}
		case c == ']' && inClass:
			inClass = false
			b.WriteByte(c)
		default:
			b.WriteByte(c)
		}
	}
	return b.String(), nil
}
