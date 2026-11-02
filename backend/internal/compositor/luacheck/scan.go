package luacheck

import "strings"

// What a line-level edit needs to know of Lua source: where its strings and
// comments are. Lua 5.4's additions to 5.1 (`//`, `<const>`, `goto`,
// bitwise operators) change none of that, so this reads 5.4 files that
// gopher-lua can't parse.

// longBracket is the length of a long bracket opening at i ("[[", "[==["),
// else 0
func longBracket(text string, i int) int {
	if i >= len(text) || text[i] != '[' {
		return 0
	}
	j := i + 1
	for j < len(text) && text[j] == '=' {
		j++
	}
	if j < len(text) && text[j] == '[' {
		return j - i + 1
	}
	return 0
}

// skipToken: if a string or comment starts at i, the index after it, else
// -1
func skipToken(text string, i int) int {
	c := text[i]
	if c == '"' || c == '\'' {
		j := i + 1
		for j < len(text) && text[j] != c {
			if text[j] == '\\' {
				j++
			} else if text[j] == '\n' {
				return j
			}
			j++
		}
		return j + 1
	}
	closing := func(from, n int) int {
		end := strings.Index(text[from:], "]"+strings.Repeat("=", n-2)+"]")
		if end < 0 {
			return len(text)
		}
		return from + end + n
	}
	if strings.HasPrefix(text[i:], "--") {
		if n := longBracket(text, i+2); n > 0 {
			return closing(i+2+n, n)
		}
		end := strings.IndexByte(text[i:], '\n')
		if end < 0 {
			return len(text)
		}
		return i + end
	}
	if c == '[' {
		if n := longBracket(text, i); n > 0 {
			return closing(i+n, n)
		}
	}
	return -1
}

// span is one string or comment: [start, end)
type span struct{ start, end int }

// tokens are text's strings and comments, in order
func tokens(text string) []span {
	var out []span
	for i := 0; i < len(text); {
		end := skipToken(text, i)
		if end < 0 {
			i++
			continue
		}
		out = append(out, span{i, min(end, len(text))})
		i = end
	}
	return out
}

// CodeOnly is text with its strings and comments blanked out (newlines
// kept), so positions still line up.
func CodeOnly(text string) string {
	out := []byte(text)
	for _, t := range tokens(text) {
		for j := t.start; j < t.end; j++ {
			if out[j] != '\n' {
				out[j] = ' '
			}
		}
	}
	return string(out)
}

// InCode is, for each line of text, whether it starts outside any string
// or comment (a line within a long string or block comment doesn't).
func InCode(text string) []bool {
	spans := tokens(text)
	var out []bool
	k := 0
	for start := 0; ; {
		for k < len(spans) && spans[k].end <= start {
			k++
		}
		out = append(out, k == len(spans) || spans[k].start >= start)
		nl := strings.IndexByte(text[start:], '\n')
		if nl < 0 {
			return out
		}
		start += nl + 1
	}
}

var (
	// Words opening a block that `end` (or `until`) closes: `while … do`
	// and `for … do` count once, by their `do`
	blockOpeners = map[string]bool{"function": true, "do": true, "if": true, "repeat": true}
	blockClosers = map[string]bool{"end": true, "until": true}
	// Words that only continue a block opened on another line
	blockMiddles = map[string]bool{"else": true, "elseif": true, "then": false}
)

// WholeLines reports whether each of lines (1-based) of src holds only
// whole statements, so commenting it out, or taking that comment away,
// leaves the rest as it was: it starts and ends outside any string or
// comment, its brackets close on it, and so do the blocks it opens. A line
// that only continues a block (else, elseif) isn't whole.
func WholeLines(src string, lines []int) bool {
	starts := []int{0}
	for i := 0; i < len(src); i++ {
		if src[i] == '\n' {
			starts = append(starts, i+1)
		}
	}
	spans := tokens(src)
	code := CodeOnly(src)
	for _, n := range lines {
		if n < 1 || n > len(starts) {
			return false
		}
		start, end := starts[n-1], len(src)
		if n < len(starts) {
			end = starts[n] - 1
		}
		for _, t := range spans {
			// One begun before the line, or going on past its newline
			if (t.start < start && t.end > start) || (t.start < end && t.end > end) {
				return false
			}
		}
		if !balanced(code[start:end]) {
			return false
		}
	}
	return true
}

// balanced: a line of code (strings and comments blanked) closes every
// bracket and block it opens, and none it didn't
func balanced(line string) bool {
	depth := 0
	for i := 0; i < len(line); i++ {
		switch line[i] {
		case '(', '[', '{':
			depth++
		case ')', ']', '}':
			if depth--; depth < 0 {
				return false
			}
		}
	}
	if depth != 0 {
		return false
	}
	blocks := 0
	for _, word := range strings.FieldsFunc(line, func(r rune) bool {
		return !(r == '_' || r >= '0' && r <= '9' || r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z')
	}) {
		switch {
		case blockOpeners[word]:
			blocks++
		case blockClosers[word]:
			if blocks--; blocks < 0 {
				return false
			}
		case blockMiddles[word] && blocks == 0:
			return false
		}
	}
	return blocks == 0
}
