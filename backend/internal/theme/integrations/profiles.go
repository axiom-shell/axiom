package integrations

import (
	"bufio"
	"bytes"
	"path"
	"strings"
)

// ProfileDirs are the profile folders a browser's profiles.ini (data,
// read from the path ini) lists, relative ones from the file's folder.
func ProfileDirs(ini string, data []byte) []string {
	var out []string
	add := func(section map[string]string) {
		if section["path"] == "" {
			return
		}
		dir := section["path"]
		if section["isrelative"] != "0" {
			dir = path.Join(path.Dir(ini), dir)
		}
		out = append(out, dir)
	}
	var section map[string]string
	sc := bufio.NewScanner(bytes.NewReader(data))
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if name, ok := strings.CutPrefix(line, "["); ok {
			if section != nil {
				add(section)
			}
			section = nil
			if strings.HasPrefix(name, "Profile") {
				section = map[string]string{}
			}
		} else if k, v, ok := strings.Cut(line, "="); ok && section != nil {
			section[strings.ToLower(strings.TrimSpace(k))] = strings.TrimSpace(v)
		}
	}
	if section != nil {
		add(section)
	}
	return out
}
