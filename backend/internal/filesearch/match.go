package filesearch

import (
	"bytes"
	"strings"
	"unicode"
	"unicode/utf8"
)

// Pattern is a parsed query: tokens split on spaces, every one of which
// must match. Smart case: a query with an upper-case letter matches case
// for case, one without ignores case. A token with a "/" is fzf's path
// segments: "doc/rep" is "rep" in a folder matching "doc" (anywhere above
// it, in order), "doc/" anything under such a folder.
type Pattern struct {
	tokens []token
	cased  bool
	mask   uint32 // every token's character classes
}

type token struct {
	text []byte   // matched against the name (lower-case unless cased)
	dirs [][]byte // folder segments before it, outermost first
	mask uint32   // text's character classes
}

// maxTokens is how many tokens a pattern keeps (the words after are
// ignored): a search keeps two tables the index's size per token, so
// pasted text must not make it allocate (and keep) hundreds of them
const maxTokens = 8

// ParsePattern parses typed text.
func ParsePattern(q string) Pattern {
	p := Pattern{}
	for _, r := range q {
		if unicode.IsUpper(r) {
			p.cased = true
			break
		}
	}
	for _, word := range strings.Fields(q) {
		if !p.cased {
			word = strings.ToLower(word)
		}
		var t token
		segs := strings.Split(word, "/")
		for _, s := range segs[:len(segs)-1] {
			if s != "" {
				t.dirs = append(t.dirs, []byte(s))
			}
		}
		t.text = []byte(segs[len(segs)-1])
		if len(t.text) == 0 && len(t.dirs) == 0 {
			continue
		}
		t.mask = maskOf(t.text)
		p.mask |= t.mask
		for _, d := range t.dirs {
			p.mask |= maskOf(d)
		}
		p.tokens = append(p.tokens, t)
		if len(p.tokens) == maxTokens {
			break
		}
	}
	return p
}

// Empty: the query had nothing to match.
func (p Pattern) Empty() bool { return len(p.tokens) == 0 }

// maskOf is a name's character classes, case ignored: a bit per letter,
// one for digits, '.', '-', '_', ' ', and one for anything else. A name
// can match a token only if its mask (with its folders') holds the
// token's: the cheap test that skips most of the index.
func maskOf(name []byte) uint32 {
	var m uint32
	for _, c := range name {
		switch {
		case c >= 'a' && c <= 'z':
			m |= 1 << (c - 'a')
		case c >= 'A' && c <= 'Z':
			m |= 1 << (c - 'A')
		case c >= '0' && c <= '9':
			m |= 1 << 26
		case c == '.':
			m |= 1 << 27
		case c == '-':
			m |= 1 << 28
		case c == '_':
			m |= 1 << 29
		case c == ' ':
			m |= 1 << 30
		default:
			m |= 1 << 31
		}
	}
	return m
}

// lowerInto is name lower-cased into buf (ASCII in place; anything else
// through unicode), reusing buf's room.
func lowerInto(buf, name []byte) []byte {
	buf = buf[:0]
	for i := 0; i < len(name); i++ {
		c := name[i]
		if c >= utf8.RuneSelf {
			return append(buf, []byte(strings.ToLower(string(name[i:])))...)
		}
		if c >= 'A' && c <= 'Z' {
			c += 'a' - 'A'
		}
		buf = append(buf, c)
	}
	return buf
}

// Score is how well text matches q, both already in the case they're
// compared in: 100 exact, 80 prefix, 65 at a word start, 50 inside, 5-30
// for the letters in order (closer is higher), 0 for no match. It is the
// Go twin of Search.score (qml/components/methods/Search.qml): keep the
// two the same, so file rows rank against apps fairly. (It counts bytes
// where the JS counts UTF-16 units: only a fuzzy span over non-ASCII
// names differs.)
func Score(text, q []byte) int {
	if len(text) == 0 || len(q) == 0 {
		return 0
	}
	if bytes.Equal(text, q) {
		return 100
	}
	if len(text) > len(q) && bytes.Equal(text[:len(q)], q) {
		return 80
	}
	if at := bytes.Index(text, q); at > 0 {
		switch text[at-1] {
		case ' ', '\t', '-', '_', '.', '/':
			return 65
		}
		return 50
	}
	if len(q) < 2 {
		return 0
	}
	matched, first, last := 0, -1, 0
	for i := 0; i < len(text) && matched < len(q); i++ {
		if text[i] == q[matched] {
			if first < 0 {
				first = i
			}
			last = i
			matched++
		}
	}
	if matched < len(q) {
		return 0
	}
	return max(5, 30-2*(last-first+1-len(q)))
}

// MatchName scores a bare name (a folder's listing) against the tokens,
// their folder segments left out: the mean of their Scores, 0 when one
// doesn't match.
func (p Pattern) MatchName(name string) float64 {
	if len(p.tokens) == 0 {
		return 0
	}
	n := []byte(name)
	if !p.cased {
		n = lowerInto(nil, n)
	}
	total := 0
	for _, t := range p.tokens {
		if len(t.text) == 0 {
			total += 50
			continue
		}
		s := Score(n, t.text)
		if s == 0 {
			return 0
		}
		total += s
	}
	return float64(total) / float64(len(p.tokens))
}
