package windowrules

import "strings"

// KindFor is the kind a rule made from a window with facts f starts with
// (Q1): its app id, a Steam game id for steam_app_N, else its process,
// else its title; one condition, op "is". Empty facts: appId is "".
func KindFor(f Facts) Kind {
	c := Condition{Field: FieldAppID, Op: OpIs, Value: f.AppID}
	switch {
	case f.AppID != "":
		if n, ok := strings.CutPrefix(f.AppID, "steam_app_"); ok && isDigits(n) {
			c = Condition{Field: FieldSteamGame, Op: OpIs, Value: n}
		}
	case f.Process != nil && f.Process.Name != "":
		c = Condition{Field: FieldProcess, Op: OpIs, Value: f.Process.Name}
	case f.Title != "":
		c = Condition{Field: FieldTitle, Op: OpIs, Value: f.Title}
	}
	return Kind{Conditions: []Condition{c}}
}

func isDigits(s string) bool { return s != "" && strings.Trim(s, "0123456789") == "" }
