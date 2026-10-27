// Package ical reads iCalendar (RFC 5545) text for the calendars: content
// lines into components and their properties. Pure: no I/O.
package ical

import (
	"errors"
	"fmt"
	"strings"
)

// Param is a property parameter, its value unquoted.
type Param struct {
	Name, Value string
}

// Prop is one content line: NAME;PARAM=…:value (the value still escaped).
type Prop struct {
	Name   string
	Params []Param
	Value  string
}

// Param is the named parameter's value ("" when absent).
func (p Prop) Param(name string) string {
	for _, param := range p.Params {
		if param.Name == name {
			return param.Value
		}
	}
	return ""
}

// Text is a TEXT value unescaped.
func (p Prop) Text() string {
	if !strings.Contains(p.Value, `\`) {
		return p.Value
	}
	var b strings.Builder
	for i := 0; i < len(p.Value); i++ {
		c := p.Value[i]
		if c == '\\' && i+1 < len(p.Value) {
			i++
			switch p.Value[i] {
			case 'n', 'N':
				b.WriteByte('\n')
			default:
				b.WriteByte(p.Value[i])
			}
			continue
		}
		b.WriteByte(c)
	}
	return b.String()
}

// Component is BEGIN:NAME … END:NAME, with its properties in order.
type Component struct {
	Name     string
	Props    []Prop
	Children []*Component
}

// Get is the first property named name, nil without one.
func (c *Component) Get(name string) *Prop {
	for i := range c.Props {
		if c.Props[i].Name == name {
			return &c.Props[i]
		}
	}
	return nil
}

// Text is the first property named name as text ("" without one).
func (c *Component) Text(name string) string {
	if p := c.Get(name); p != nil {
		return p.Text()
	}
	return ""
}

// Parse reads the first top-level component of text (normally a
// VCALENDAR). Lines are unfolded first; an unclosed component ends with
// the text.
func Parse(text string) (*Component, error) {
	text = strings.ReplaceAll(strings.ReplaceAll(text, "\r\n", "\n"), "\r", "\n")
	text = strings.NewReplacer("\n ", "", "\n\t", "").Replace(text)
	var root *Component
	var stack []*Component
	for n, line := range strings.Split(text, "\n") {
		if strings.TrimSpace(line) == "" {
			continue
		}
		prop, err := parseLine(line)
		if err != nil {
			return nil, fmt.Errorf("line %d: %w", n+1, err)
		}
		switch prop.Name {
		case "BEGIN":
			c := &Component{Name: strings.ToUpper(strings.TrimSpace(prop.Value))}
			if len(stack) > 0 {
				top := stack[len(stack)-1]
				top.Children = append(top.Children, c)
			} else if root == nil {
				root = c
			} else {
				return root, nil
			}
			stack = append(stack, c)
		case "END":
			if len(stack) == 0 || stack[len(stack)-1].Name != strings.ToUpper(strings.TrimSpace(prop.Value)) {
				return nil, fmt.Errorf("line %d: END:%s without its BEGIN", n+1, prop.Value)
			}
			stack = stack[:len(stack)-1]
		default:
			if len(stack) == 0 {
				return nil, fmt.Errorf("line %d: %s outside a component", n+1, prop.Name)
			}
			top := stack[len(stack)-1]
			top.Props = append(top.Props, prop)
		}
	}
	if root == nil {
		return nil, errors.New("no BEGIN line")
	}
	return root, nil
}

// parseLine splits NAME *(;PARAM=VALUE[,VALUE]) : VALUE, quotes allowed
// around parameter values
func parseLine(line string) (Prop, error) {
	end := strings.IndexAny(line, ";:")
	if end <= 0 {
		return Prop{}, fmt.Errorf("not a content line: %q", line)
	}
	p := Prop{Name: strings.ToUpper(line[:end])}
	i := end
	for line[i] == ';' {
		eq := strings.IndexByte(line[i:], '=')
		if eq < 0 {
			return Prop{}, fmt.Errorf("parameter without a value: %q", line)
		}
		name := strings.ToUpper(line[i+1 : i+eq])
		i += eq + 1
		var value strings.Builder
		for i < len(line) && line[i] != ';' && line[i] != ':' {
			if line[i] == '"' {
				close := strings.IndexByte(line[i+1:], '"')
				if close < 0 {
					return Prop{}, fmt.Errorf("unclosed quote: %q", line)
				}
				value.WriteString(line[i+1 : i+1+close])
				i += close + 2
				continue
			}
			value.WriteByte(line[i])
			i++
		}
		p.Params = append(p.Params, Param{Name: name, Value: value.String()})
		if i >= len(line) {
			return Prop{}, fmt.Errorf("no value: %q", line)
		}
	}
	p.Value = line[i+1:]
	return p, nil
}
