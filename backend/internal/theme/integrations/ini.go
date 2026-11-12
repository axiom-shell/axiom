package integrations

import (
	"regexp"
	"slices"
	"strings"
)

// Keys is what MergeKDE changed in an ini file, per key (never per group,
// so a user's edit of another key in the same group never blocks an undo):
// a group's keys and their values, nil for a key that wasn't there.
type Keys struct {
	Groups map[string]map[string]*string `json:"groups"`
	// Created are the groups that weren't in the file
	Created []string `json:"created,omitempty"`
}

var iniKeyLine = regexp.MustCompile(`^([^=\[#;\s][^=]*)=(.*)$`)

// iniValues is a file's key lines by group ("" before the first header).
func iniValues(text []byte) (groups map[string]map[string]string, order []string) {
	groups = map[string]map[string]string{"": {}}
	cur := ""
	for _, line := range splitLines(text) {
		if iniGroup.MatchString(line) {
			cur = line[1 : len(line)-1]
			if groups[cur] == nil {
				groups[cur] = map[string]string{}
				order = append(order, cur)
			}
		} else if m := iniKeyLine.FindStringSubmatch(line); m != nil {
			if _, seen := groups[cur][m[1]]; !seen {
				groups[cur][m[1]] = m[2]
			}
		}
	}
	return groups, order
}

// KeysChanged is the keys after has that before hasn't or has other
// values of: what they were (prior) and now are (wrote).
func KeysChanged(before, after []byte) (prior, wrote Keys) {
	was, _ := iniValues(before)
	now, order := iniValues(after)
	prior, wrote = Keys{Groups: map[string]map[string]*string{}}, Keys{Groups: map[string]map[string]*string{}}
	for _, g := range append([]string{""}, order...) {
		for k, v := range now[g] {
			old, had := was[g][k]
			if had && old == v {
				continue
			}
			if prior.Groups[g] == nil {
				prior.Groups[g], wrote.Groups[g] = map[string]*string{}, map[string]*string{}
			}
			nv := v
			wrote.Groups[g][k] = &nv
			if had {
				ov := old
				prior.Groups[g][k] = &ov
			} else {
				prior.Groups[g][k] = nil
			}
		}
		if _, existed := was[g]; !existed && g != "" && len(prior.Groups[g]) > 0 {
			prior.Created = append(prior.Created, g)
		}
	}
	return prior, wrote
}

// MergeKeys is two records of one file's changes as one: the first's
// prior values (what was there before axiom), the last's written ones.
func MergeKeys(old, now Keys) Keys {
	out := Keys{Groups: map[string]map[string]*string{}, Created: slices.Clone(old.Created)}
	for _, src := range []Keys{now, old} {
		for g, keys := range src.Groups {
			if out.Groups[g] == nil {
				out.Groups[g] = map[string]*string{}
			}
			for k, v := range keys {
				out.Groups[g][k] = v
			}
		}
	}
	for _, g := range now.Created {
		if !slices.Contains(out.Created, g) {
			out.Created = append(out.Created, g)
		}
	}
	return out
}

// MergeWrote is wrote records merged, the latter's values winning.
func MergeWrote(old, now Keys) Keys {
	out := MergeKeys(now, old)
	out.Created = nil
	return out
}

// KeysAre says which of wrote's keys the text still has as written: all
// of them (changed is empty), or those that differ.
func KeysAre(text []byte, wrote Keys) (changed []string) {
	have, _ := iniValues(text)
	for g, keys := range wrote.Groups {
		for k, v := range keys {
			if cur, ok := have[g][k]; v != nil && (!ok || cur != *v) {
				changed = append(changed, g+"/"+k)
			}
		}
	}
	slices.Sort(changed)
	return changed
}

// RestoreKeys puts each key of wrote that still has its written value
// back to its prior (a key that wasn't there is removed), and a group axiom
// created is removed once it's empty. Every key that differs from what
// axiom wrote is left and named in changed.
func RestoreKeys(text []byte, prior, wrote Keys) (out []byte, changed []string) {
	lines := splitLines(text)
	cur := ""
	var drop []int
	remaining := Keys{Groups: map[string]map[string]*string{}}
	for g, keys := range wrote.Groups {
		remaining.Groups[g] = map[string]*string{}
		for k, v := range keys {
			remaining.Groups[g][k] = v
		}
	}
	for i, line := range lines {
		if iniGroup.MatchString(line) {
			cur = line[1 : len(line)-1]
			continue
		}
		m := iniKeyLine.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		w, ok := wrote.Groups[cur][m[1]]
		if !ok || w == nil || *w != m[2] {
			continue
		}
		if p := prior.Groups[cur][m[1]]; p != nil {
			lines[i] = m[1] + "=" + *p
		} else {
			drop = append(drop, i)
		}
		// each key once: a repeated one stays
		delete(remaining.Groups[cur], m[1])
	}
	changed = KeysAre(text, remaining)
	for j := len(drop) - 1; j >= 0; j-- {
		lines = slices.Delete(lines, drop[j], drop[j]+1)
	}
	for _, g := range prior.Created {
		lines = dropEmptyGroup(lines, g)
	}
	if len(lines) == 0 {
		return nil, changed
	}
	return []byte(strings.Join(lines, "\n") + "\n"), changed
}

// dropEmptyGroup removes group's header and the blank line before it when
// it holds no key.
func dropEmptyGroup(lines []string, group string) []string {
	for i, line := range lines {
		if line != "["+group+"]" {
			continue
		}
		end := i + 1
		for end < len(lines) && blank.MatchString(lines[end]) {
			end++
		}
		if end < len(lines) && !iniGroup.MatchString(lines[end]) {
			return lines
		}
		// The header and the blank line before it; the blank lines after
		// belong to what follows (another section's separator)
		start := i
		if start > 0 && blank.MatchString(lines[start-1]) {
			start--
		}
		return slices.Delete(slices.Clone(lines), start, i+1)
	}
	return lines
}

// OnlyKeys is k with just the keys named ("group/key"), and the groups
// created.
func OnlyKeys(k Keys, names []string) Keys {
	out := Keys{Groups: map[string]map[string]*string{}, Created: k.Created}
	for g, keys := range k.Groups {
		for key, v := range keys {
			if slices.Contains(names, g+"/"+key) {
				if out.Groups[g] == nil {
					out.Groups[g] = map[string]*string{}
				}
				out.Groups[g][key] = v
			}
		}
	}
	return out
}
