// Package yamlsrc is the YAML source of the config schema
// (config/schema/): a strict YAML reader, the assembler that joins the
// files into the one JSON schema everything else reads, and the checks that
// refuse a mistyped keyword or annotation. Pure: files come through an
// fs.FS; finding the tree on disk and reading it is package tree's.
//
// Strict means YAML can't mean something other than it looks: no anchors,
// aliases or merge keys, no tags beyond the plain types, no timestamps,
// unquoted YAML 1.1 booleans (on, off, yes, no, y, n, which are enum values
// here) or bare nulls, no duplicate or non-string keys, no NaN, Inf or
// integers JSON can't hold exactly, one document per file.
package yamlsrc

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"math"
	"regexp"
	"strconv"
	"strings"

	"go.yaml.in/yaml/v3"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// MaxFileSize bounds one source file.
const MaxFileSize = 1 << 20

// Error is a problem at a place in a source file.
type Error struct {
	File   string
	Line   int
	Column int
	Msg    string
}

func (e *Error) Error() string {
	if e.Line > 0 {
		return fmt.Sprintf("%s:%d:%d: %s", e.File, e.Line, e.Column, e.Msg)
	}
	return fmt.Sprintf("%s: %s", e.File, e.Msg)
}

// Errors is several problems, reported together.
type Errors []*Error

func (es Errors) Error() string {
	parts := make([]string, len(es))
	for i, e := range es {
		parts[i] = e.Error()
	}
	return strings.Join(parts, "\n")
}

func errAt(file string, n *yaml.Node, format string, args ...any) *Error {
	e := &Error{File: file, Msg: fmt.Sprintf(format, args...)}
	if n != nil {
		e.Line, e.Column = n.Line, n.Column
	}
	return e
}

// Parse reads one strict YAML document as a JSON value.
func Parse(file string, data []byte) (any, error) {
	v, _, err := ParsePositions(file, data, nil)
	return v, err
}

// ParsePositions is Parse, recording where keys were into pos (made when
// nil).
func ParsePositions(file string, data []byte, pos Positions) (any, Positions, error) {
	if pos == nil {
		pos = Positions{}
	}
	if len(data) > MaxFileSize {
		return nil, pos, &Error{File: file, Msg: fmt.Sprintf("larger than %d bytes", MaxFileSize)}
	}
	dec := yaml.NewDecoder(bytes.NewReader(data))
	var doc yaml.Node
	if err := dec.Decode(&doc); err != nil {
		if errors.Is(err, io.EOF) {
			return nil, pos, &Error{File: file, Msg: "empty file"}
		}
		return nil, pos, &Error{File: file, Msg: err.Error()}
	}
	var extra yaml.Node
	if err := dec.Decode(&extra); !errors.Is(err, io.EOF) {
		return nil, pos, errAt(file, &extra, "more than one YAML document")
	}
	p := &reader{file: file, pos: pos}
	v := p.node(&doc)
	if len(p.errs) > 0 {
		return nil, pos, p.errs
	}
	return v, pos, nil
}

type reader struct {
	file string
	errs Errors
	pos  Positions
}

// Positions are where each object's keys were in the YAML, for errors
// found after parsing.
type Positions map[*jsonx.Object]map[string]position

type position struct {
	file         string
	line, column int
}

// At is the place of key in obj, as an Error with msg.
func (ps Positions) At(obj *jsonx.Object, key, fallbackFile, msg string) *Error {
	if p, ok := ps[obj][key]; ok {
		return &Error{File: p.file, Line: p.line, Column: p.column, Msg: msg}
	}
	return &Error{File: fallbackFile, Msg: msg}
}

func (p *reader) fail(n *yaml.Node, format string, args ...any) {
	p.errs = append(p.errs, errAt(p.file, n, format, args...))
}

var (
	decimalInt   = regexp.MustCompile(`^-?(0|[1-9][0-9]*)$`)
	decimalFloat = regexp.MustCompile(`^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?$`)
	// Plain scalars YAML 1.1 reads as booleans; YAML 1.2 (and this
	// reader) as strings: quote them so there's no doubt
	yaml11Bools = map[string]bool{"y": true, "n": true, "yes": true, "no": true, "on": true, "off": true}
)

func (p *reader) node(n *yaml.Node) any {
	if n.Anchor != "" {
		p.fail(n, "anchors (&%s) aren't allowed: write the value out", n.Anchor)
	}
	switch n.Kind {
	case yaml.DocumentNode:
		if len(n.Content) != 1 {
			p.fail(n, "a document holds one value")
			return nil
		}
		return p.node(n.Content[0])
	case yaml.AliasNode:
		p.fail(n, "aliases (*%s) aren't allowed: write the value out", n.Value)
		return nil
	case yaml.MappingNode:
		if n.Tag != "!!map" {
			p.fail(n, "tag %s isn't allowed", n.Tag)
		}
		obj := jsonx.NewObject()
		for i := 0; i+1 < len(n.Content); i += 2 {
			k, v := n.Content[i], n.Content[i+1]
			if k.Tag == "!!merge" {
				p.fail(k, "merge keys (<<) aren't allowed: write the keys out")
				continue
			}
			if k.Kind != yaml.ScalarNode || k.Tag != "!!str" {
				p.fail(k, "a key must be a string (quote %q)", k.Value)
				continue
			}
			if k.Style == 0 && yaml11Bools[strings.ToLower(k.Value)] {
				p.fail(k, "quote the key %q (YAML 1.1 reads it as a boolean)", k.Value)
			}
			if obj.Has(k.Value) {
				p.fail(k, "duplicate key %q", k.Value)
				continue
			}
			obj.Set(k.Value, p.node(v))
			if p.pos[obj] == nil {
				p.pos[obj] = map[string]position{}
			}
			p.pos[obj][k.Value] = position{p.file, k.Line, k.Column}
		}
		return obj
	case yaml.SequenceNode:
		if n.Tag != "!!seq" {
			p.fail(n, "tag %s isn't allowed", n.Tag)
		}
		arr := jsonx.Arr()
		for _, item := range n.Content {
			arr.Append(p.node(item))
		}
		return arr
	case yaml.ScalarNode:
		return p.scalar(n)
	}
	p.fail(n, "unexpected YAML node")
	return nil
}

func (p *reader) scalar(n *yaml.Node) any {
	quoted := n.Style&(yaml.DoubleQuotedStyle|yaml.SingleQuotedStyle|yaml.LiteralStyle|yaml.FoldedStyle) != 0
	switch n.Tag {
	case "!!str":
		if !quoted && yaml11Bools[strings.ToLower(n.Value)] {
			p.fail(n, "quote %q (YAML 1.1 reads it as a boolean)", n.Value)
		}
		return n.Value
	case "!!bool":
		switch n.Value {
		case "true":
			return true
		case "false":
			return false
		}
		p.fail(n, "write booleans as true or false, not %q", n.Value)
		return nil
	case "!!null":
		if n.Value != "null" {
			p.fail(n, "a missing value: write null if null is meant")
		}
		return nil
	case "!!int":
		if !decimalInt.MatchString(n.Value) {
			p.fail(n, "write integers in decimal, not %q", n.Value)
			return nil
		}
		i, err := strconv.ParseInt(n.Value, 10, 64)
		if err != nil || i > 1<<53 || i < -(1<<53) {
			p.fail(n, "%s is too large to hold exactly", n.Value)
			return nil
		}
		return float64(i)
	case "!!float":
		if !decimalFloat.MatchString(n.Value) {
			p.fail(n, "write numbers in decimal, not %q (no .inf or .nan)", n.Value)
			return nil
		}
		f, err := strconv.ParseFloat(n.Value, 64)
		if err != nil || math.IsInf(f, 0) {
			p.fail(n, "%s is out of range", n.Value)
			return nil
		}
		return f
	}
	p.fail(n, "%s values aren't allowed (quote it for a string)", strings.TrimPrefix(n.Tag, "!!"))
	return nil
}
