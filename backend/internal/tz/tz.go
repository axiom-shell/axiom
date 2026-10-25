// Package tz is the system's time zones for the shell's clocks (`tz.zones`,
// `tz.offsets`, the shell's TimeZoneManager): the zone names tzdata lists,
// and a zone's UTC offset now, both read from the zoneinfo directory
// ($TZDIR, else /usr/share/zoneinfo) the system's own tools use.
package tz

import (
	"bufio"
	"bytes"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"time"
)

// DefaultDir is the zoneinfo directory without $TZDIR.
const DefaultDir = "/usr/share/zoneinfo"

// Dir is the zoneinfo directory: $TZDIR (NixOS has no
// /usr/share/zoneinfo), else DefaultDir.
func Dir(getenv func(string) string) string {
	if dir := getenv("TZDIR"); dir != "" {
		return dir
	}
	return DefaultDir
}

// A zone name: never absolute, never climbing out of the directory
var validZone = regexp.MustCompile(`^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$`)

// ParseZi reads tzdata.zi's zone names: its zones (`Z name …`) and links
// (`L target name`), sorted, each once.
func ParseZi(r io.Reader) []string {
	var zones []string
	sc := bufio.NewScanner(r)
	for sc.Scan() {
		f := strings.Fields(sc.Text())
		switch {
		case len(f) >= 2 && f[0] == "Z":
			zones = append(zones, f[1])
		case len(f) >= 3 && f[0] == "L":
			zones = append(zones, f[2])
		}
	}
	slices.Sort(zones)
	return slices.Compact(zones)
}

// Zones are the zone names in dir: tzdata.zi's list, else every zoneinfo
// file found under it (outside the posix/ and right/ copies).
func Zones(dir string) []string {
	if f, err := os.Open(filepath.Join(dir, "tzdata.zi")); err == nil {
		defer f.Close()
		if zones := ParseZi(f); len(zones) > 0 {
			return zones
		}
	}
	var zones []string
	filepath.WalkDir(dir, func(path string, e fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		name, _ := filepath.Rel(dir, path)
		if e.IsDir() {
			if name == "posix" || name == "right" {
				return filepath.SkipDir
			}
			return nil
		}
		if validZone.MatchString(name) && name != "localtime" && name != "posixrules" && isTZif(path) {
			zones = append(zones, name)
		}
		return nil
	})
	slices.Sort(zones)
	return zones
}

func isTZif(path string) bool {
	f, err := os.Open(path)
	if err != nil {
		return false
	}
	defer f.Close()
	head := make([]byte, 4)
	_, err = io.ReadFull(f, head)
	return err == nil && bytes.Equal(head, []byte("TZif"))
}

// Offsets are the zones' UTC offsets at now, in minutes east; a zone dir
// has no file for is left out.
func Offsets(dir string, zones []string, now time.Time) map[string]int {
	out := map[string]int{}
	for _, zone := range zones {
		if !validZone.MatchString(zone) {
			continue
		}
		data, err := os.ReadFile(filepath.Join(dir, zone))
		if err != nil {
			continue
		}
		loc, err := time.LoadLocationFromTZData(zone, data)
		if err != nil {
			continue
		}
		_, offset := now.In(loc).Zone()
		out[zone] = offset / 60
	}
	return out
}
