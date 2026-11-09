package filesearch

import (
	"bytes"
	"encoding/xml"
	"time"
)

// Recent is a file from recently-used.xbel: GTK's (and many apps') list
// of what was opened, read, never written.
type Recent struct {
	Path string
	Time int64 // ms: its last visit, change or addition
}

type xbelFile struct {
	Bookmarks []struct {
		Href     string `xml:"href,attr"`
		Added    string `xml:"added,attr"`
		Modified string `xml:"modified,attr"`
		Visited  string `xml:"visited,attr"`
	} `xml:"bookmark"`
}

// ParseXBEL reads recently-used.xbel's local files, in the file's order;
// a file that doesn't parse gives none.
func ParseXBEL(data []byte) []Recent {
	var f xbelFile
	d := xml.NewDecoder(bytes.NewReader(data))
	d.Strict = false
	if err := d.Decode(&f); err != nil {
		return nil
	}
	var out []Recent
	for _, b := range f.Bookmarks {
		path := PathOfURI(b.Href)
		if path == "" {
			continue
		}
		var last int64
		for _, s := range []string{b.Added, b.Modified, b.Visited} {
			if t, err := time.Parse(time.RFC3339Nano, s); err == nil {
				last = max(last, t.UnixMilli())
			}
		}
		out = append(out, Recent{Path: path, Time: last})
	}
	return out
}
