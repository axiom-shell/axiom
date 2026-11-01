// Package kdl parses niri's config: the subset of KDL 1 and 2 niri configs
// use, into nodes that keep where they start (for the bind merge's edits).
// render writes KDL. Pure: no I/O.
package kdl

import (
	"fmt"
	"math"
	"regexp"
	"strconv"
	"strings"
)

// Node is a KDL node: its name, arguments, properties (in the order they
// first appear), children (nil without a block) and where it starts
// (Line 1-based; Col and Start in characters, not bytes).
type Node struct {
	Name     string
	Args     []any
	Props    Props
	Children []*Node
	Line     int
	Col      int
	Start    int
}

// A value is a string, an int64, a float64, a bool or nil.

// Props are a node's properties in the order they first appear (a later
// one of the same key replaces the value, keeping its place).
type Props struct {
	keys   []string
	values map[string]any
}

// Get returns the property's value and whether it's set.
func (p Props) Get(key string) (any, bool) {
	v, ok := p.values[key]
	return v, ok
}

// Keys are the property names in order.
func (p Props) Keys() []string { return append([]string(nil), p.keys...) }

// Len is the number of properties.
func (p Props) Len() int { return len(p.keys) }

func (p *Props) set(key string, v any) {
	if p.values == nil {
		p.values = map[string]any{}
	}
	if _, ok := p.values[key]; !ok {
		p.keys = append(p.keys, key)
	}
	p.values[key] = v
}

// Child is the first child named name, or nil.
func (n *Node) Child(name string) *Node {
	if n == nil {
		return nil
	}
	for _, c := range n.Children {
		if c.Name == name {
			return c
		}
	}
	return nil
}

// Error is a syntax error.
type Error struct {
	Line    int
	Message string
}

func (e *Error) Error() string { return fmt.Sprintf("line %d: %s", e.Line, e.Message) }

// Parse returns the nodes of a KDL document.
func Parse(text string) (nodes []*Node, err error) {
	p := &parser{text: []rune(text)}
	defer func() {
		if r := recover(); r != nil {
			e, ok := r.(*Error)
			if !ok {
				panic(r)
			}
			nodes, err = nil, e
		}
	}()
	return p.nodes(false), nil
}

// What can't be part of a bare identifier
const notIdent = "\\/(){}<>;[]=,\"# \t\n\r"

var (
	number = regexp.MustCompile(`^[+-]?(0x[0-9a-fA-F_]+|0o[0-7_]+|0b[01_]+|[0-9][0-9_]*(\.[0-9][0-9_]*)?([eE][+-]?[0-9_]+)?)$`)
	isInt  = regexp.MustCompile(`^[+-]?0[xob]|^[+-]?[0-9]+$`)
)

var keywords = map[string]any{"true": true, "false": false, "null": nil, "#true": true, "#false": false, "#null": nil,
	"#inf": math.Inf(1), "#-inf": math.Inf(-1), "#nan": math.NaN()}

var escapes = map[rune]rune{'n': '\n', 'r': '\r', 't': '\t', '\\': '\\', '/': '/', '"': '"', 'b': '\b', 'f': '\f', 's': ' '}

type parser struct {
	text []rune
	i    int
}

func (p *parser) fail(format string, args ...any) {
	line := 1
	for _, r := range p.text[:min(p.i, len(p.text))] {
		if r == '\n' {
			line++
		}
	}
	panic(&Error{Line: line, Message: fmt.Sprintf(format, args...)})
}

// peek is the character n ahead, 0 past the end
func (p *parser) peek(n int) rune {
	if j := p.i + n; j < len(p.text) {
		return p.text[j]
	}
	return 0
}

func (p *parser) at(s string) bool {
	r := []rune(s)
	if p.i+len(r) > len(p.text) {
		return false
	}
	return string(p.text[p.i:p.i+len(r)]) == s
}

func (p *parser) find(s string, from int) int {
	r := []rune(s)
	for j := from; j+len(r) <= len(p.text); j++ {
		if string(p.text[j:j+len(r)]) == s {
			return j
		}
	}
	return -1
}

func (p *parser) where() (line, col, start int) {
	line, lineStart := 1, 0
	for j, r := range p.text[:p.i] {
		if r == '\n' {
			line++
			lineStart = j + 1
		}
	}
	return line, p.i - lineStart, p.i
}

func (p *parser) skipBlockComment() {
	depth := 0
	for p.i < len(p.text) {
		switch {
		case p.at("/*"):
			depth++
			p.i += 2
		case p.at("*/"):
			depth--
			p.i += 2
			if depth == 0 {
				return
			}
		default:
			p.i++
		}
	}
	p.fail("unterminated /* comment")
}

// skipSpace skips whitespace and comments, and newlines too when newlines;
// a backslash continues a node on the next line
func (p *parser) skipSpace(newlines bool) {
	for p.i < len(p.text) {
		ch := p.peek(0)
		switch {
		case ch == ' ' || ch == '\t' || ch == '\uFEFF' || (newlines && (ch == '\r' || ch == '\n')):
			p.i++
		case p.at("//"):
			for p.i < len(p.text) && p.peek(0) != '\n' {
				p.i++
			}
		case p.at("/*"):
			p.skipBlockComment()
		case ch == '\\':
			p.i++
			p.skipSpace(false)
			if p.peek(0) == '\r' {
				p.i++
			}
			if p.peek(0) != '\n' {
				p.fail("a \\ continues a line only before its end")
			}
			p.i++
		default:
			return
		}
	}
}

func (p *parser) isStringStart() bool {
	ch, next := p.peek(0), p.peek(1)
	return ch == '"' || (ch == 'r' && (next == '"' || next == '#')) || (ch == '#' && (next == '"' || next == '#'))
}

// str reads a quoted, raw (r"…", r#"…"#, #"…"#) or multi-line string
func (p *parser) str() string {
	hashes := 0
	if p.peek(0) == 'r' && (p.peek(1) == '"' || p.peek(1) == '#') {
		p.i++
		for p.peek(0) == '#' {
			hashes++
			p.i++
		}
		return p.raw(hashes)
	}
	if p.peek(0) == '#' {
		for p.peek(0) == '#' {
			hashes++
			p.i++
		}
		return p.raw(hashes)
	}
	if p.at(`"""`) {
		return p.multiline()
	}
	p.i++
	var out []rune
	for {
		if p.i >= len(p.text) {
			p.fail("unterminated string")
		}
		ch := p.text[p.i]
		p.i++
		if ch == '"' {
			return string(out)
		}
		if ch != '\\' {
			out = append(out, ch)
			continue
		}
		esc := p.peek(0)
		p.i++
		switch {
		case esc == 'u':
			m := unicodeEscape.FindStringSubmatch(string(p.text[p.i:min(p.i+9, len(p.text))]))
			if m == nil {
				p.fail("bad \\u escape")
			}
			code, _ := strconv.ParseInt(m[1], 16, 32)
			out = append(out, rune(code))
			p.i += len([]rune(m[0]))
		case escapes[esc] != 0:
			out = append(out, escapes[esc])
		case esc == ' ' || esc == '\t' || esc == '\r' || esc == '\n':
			// KDL 2: a backslash eats the whitespace after it
			for c := p.peek(0); c == ' ' || c == '\t' || c == '\r' || c == '\n'; c = p.peek(0) {
				p.i++
			}
		default:
			p.fail("bad escape \\%c", esc)
		}
	}
}

var unicodeEscape = regexp.MustCompile(`^\{([0-9a-fA-F]{1,6})\}`)

func (p *parser) raw(hashes int) string {
	multi := p.at(`"""`)
	quote := `"`
	if multi {
		quote = `"""`
	}
	if !p.at(quote) {
		p.fail("raw string without its quote")
	}
	p.i += len(quote)
	end := p.find(quote+strings.Repeat("#", hashes), p.i)
	if end < 0 {
		p.fail("unterminated raw string")
	}
	value := string(p.text[p.i:end])
	p.i = end + len(quote) + hashes
	if multi {
		return dedent(value)
	}
	return value
}

func (p *parser) multiline() string {
	p.i += 3
	end := p.find(`"""`, p.i)
	if end < 0 {
		p.fail(`unterminated """ string`)
	}
	value := string(p.text[p.i:end])
	p.i = end + 3
	return dedent(value)
}

// dedent takes a multi-line string's first and last lines off, and the
// last line's indent off the rest
func dedent(value string) string {
	lines := strings.Split(value, "\n")
	if len(lines) < 2 {
		return value
	}
	indent := lines[len(lines)-1]
	out := make([]string, 0, len(lines)-2)
	for _, line := range lines[1 : len(lines)-1] {
		if strings.HasPrefix(line, indent) {
			out = append(out, line[len(indent):])
		} else {
			out = append(out, strings.TrimLeft(line, " \t\n\r\v\f"))
		}
	}
	return strings.Join(out, "\n")
}

func (p *parser) bare() string {
	start := p.i
	for p.i < len(p.text) && !strings.ContainsRune(notIdent, p.peek(0)) {
		p.i++
	}
	// KDL 2's keywords (#true) and a raw string's hashes start with #
	if p.i == start && p.peek(0) == '#' {
		p.i++
		for p.i < len(p.text) && !strings.ContainsRune(notIdent, p.peek(0)) {
			p.i++
		}
	}
	if p.i == start {
		if p.i >= len(p.text) {
			p.fail("unexpected end")
		}
		p.fail("unexpected %q", p.peek(0))
	}
	return string(p.text[start:p.i])
}

func (p *parser) typeAnnotation() {
	if p.peek(0) == '(' {
		end := p.find(")", p.i)
		if end < 0 {
			p.fail("unterminated type annotation")
		}
		p.i = end + 1
	}
}

// value reads an argument or property value
func (p *parser) value() any {
	p.typeAnnotation()
	if p.isStringStart() {
		return p.str()
	}
	word := p.bare()
	if v, ok := keywords[word]; ok {
		return v
	}
	if number.MatchString(word) {
		clean := strings.ReplaceAll(word, "_", "")
		if isInt.MatchString(clean) {
			n, err := parseInt(clean)
			if err != nil {
				p.fail("bad number %s", word)
			}
			return n
		}
		f, err := strconv.ParseFloat(clean, 64)
		if err != nil {
			p.fail("bad number %s", word)
		}
		return f
	}
	return word
}

// parseInt reads an integer as Python's int(text, 0) does: 0x, 0o and 0b
// prefixes, and no leading zeros on a decimal one but zeros themselves
func parseInt(text string) (int64, error) {
	sign, digits := "", text
	if digits != "" && (digits[0] == '+' || digits[0] == '-') {
		sign, digits = digits[:1], digits[1:]
	}
	base := 10
	if len(digits) > 1 && digits[0] == '0' {
		switch digits[1] {
		case 'x', 'X':
			base, digits = 16, digits[2:]
		case 'o', 'O':
			base, digits = 8, digits[2:]
		case 'b', 'B':
			base, digits = 2, digits[2:]
		default:
			if strings.Trim(digits, "0") != "" {
				return 0, fmt.Errorf("leading zeros")
			}
		}
	}
	n, err := strconv.ParseInt(sign+digits, base, 64)
	return n, err
}

func (p *parser) node() *Node {
	line, col, start := p.where()
	p.typeAnnotation()
	var name string
	if p.isStringStart() {
		name = p.str()
	} else {
		name = p.bare()
	}
	node := &Node{Name: name, Line: line, Col: col, Start: start}
	for {
		p.skipSpace(false)
		ch := p.peek(0)
		if p.i >= len(p.text) || ch == '\n' || ch == '\r' || ch == ';' || ch == '}' {
			if ch == ';' && p.i < len(p.text) {
				p.i++
			}
			return node
		}
		if ch == '{' {
			p.i++
			node.Children = p.nodes(true)
			return node
		}
		dashed := p.at("/-")
		if dashed {
			p.i += 2
			p.skipSpace(false)
			if p.peek(0) == '{' && p.i < len(p.text) {
				p.i++
				p.nodes(true)
				continue
			}
		}
		// An entry: a property (key=value) or an argument
		save := p.i
		key, isKey := "", false
		if p.isStringStart() {
			key, isKey = p.str(), true
		} else if p.i < len(p.text) && p.peek(0) != '(' {
			key, isKey = p.bare(), true
		}
		if isKey && p.peek(0) == '=' && p.i < len(p.text) {
			p.i++
			value := p.value()
			if !dashed {
				node.Props.set(key, value)
			}
		} else {
			p.i = save
			value := p.value()
			if !dashed {
				node.Args = append(node.Args, value)
			}
		}
	}
}

func (p *parser) nodes(inBlock bool) []*Node {
	found := []*Node{}
	for {
		p.skipSpace(true)
		for p.i < len(p.text) && p.peek(0) == ';' {
			p.i++
			p.skipSpace(true)
		}
		if p.i >= len(p.text) {
			if inBlock {
				p.fail("unterminated { block")
			}
			return found
		}
		if p.peek(0) == '}' {
			if !inBlock {
				p.fail("unexpected }")
			}
			p.i++
			return found
		}
		if p.at("/-") {
			p.i += 2
			p.skipSpace(true)
			p.node()
			continue
		}
		found = append(found, p.node())
	}
}

// Truthy is whether a value counts as set: not "", 0, false or null.
func Truthy(v any) bool {
	switch v := v.(type) {
	case nil:
		return false
	case bool:
		return v
	case string:
		return v != ""
	case int64:
		return v != 0
	case float64:
		return v != 0
	}
	return true
}

// JSON is a value as a jsonx one (numbers as float64).
func JSON(v any) any {
	if n, ok := v.(int64); ok {
		return float64(n)
	}
	return v
}
