// Package xkb reads the xkb registry (rules/evdev.xml): every keyboard
// layout with its full name, indicator, languages and variants, for the
// settings' layout picker and the full names compositors report ("German"
// is de, not "ge"). Pure: the daemon reads the file (input.layouts).
package xkb

import (
	"encoding/xml"
	"io"
	"strings"
)

// Registry is the registry's layouts, in its order.
type Registry struct {
	Layouts []Layout `json:"layouts"`
}

// Layout is one xkb layout ("de"): its indicator ("de", a short name the
// registry gives some), full name ("German"), ISO 639 languages ("ger")
// and variants.
type Layout struct {
	Name        string    `json:"name"`
	Short       string    `json:"short"`
	Description string    `json:"description"`
	Languages   []string  `json:"languages"`
	Variants    []Variant `json:"variants"`
}

// Variant is one of a layout's variants ("neo", "German (Neo 2)"); its
// languages are empty when they're the layout's.
type Variant struct {
	Name        string   `json:"name"`
	Short       string   `json:"short"`
	Description string   `json:"description"`
	Languages   []string `json:"languages"`
}

type configItem struct {
	Name        string   `xml:"name"`
	Short       string   `xml:"shortDescription"`
	Description string   `xml:"description"`
	Languages   []string `xml:"languageList>iso639Id"`
}

type document struct {
	Layouts []struct {
		Item     configItem `xml:"configItem"`
		Variants []struct {
			Item configItem `xml:"configItem"`
		} `xml:"variantList>variant"`
	} `xml:"layoutList>layout"`
}

// Parse reads a registry file. An entry without a name is left out.
func Parse(r io.Reader) (Registry, error) {
	var doc document
	d := xml.NewDecoder(r)
	// The file names its DTD only; nothing is fetched
	d.Strict = true
	if err := d.Decode(&doc); err != nil {
		return Registry{}, err
	}
	out := Registry{Layouts: []Layout{}}
	for _, l := range doc.Layouts {
		name := strings.TrimSpace(l.Item.Name)
		if name == "" {
			continue
		}
		layout := Layout{Name: name, Short: strings.TrimSpace(l.Item.Short), Description: strings.TrimSpace(l.Item.Description),
			Languages: languages(l.Item.Languages), Variants: []Variant{}}
		for _, v := range l.Variants {
			if vname := strings.TrimSpace(v.Item.Name); vname != "" {
				layout.Variants = append(layout.Variants, Variant{Name: vname, Short: strings.TrimSpace(v.Item.Short),
					Description: strings.TrimSpace(v.Item.Description), Languages: languages(v.Item.Languages)})
			}
		}
		out.Layouts = append(out.Layouts, layout)
	}
	return out, nil
}

func languages(list []string) []string {
	out := []string{}
	for _, l := range list {
		if l = strings.TrimSpace(l); l != "" {
			out = append(out, l)
		}
	}
	return out
}
