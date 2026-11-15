package windowrules

import (
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// Every message validate.go gives an issue is an English key the shell
// translates (I18n.tr), so each is listed in the editor's QML
func TestIssueMessagesAreTranslatable(t *testing.T) {
	t.Parallel()
	file, err := parser.ParseFile(token.NewFileSet(), "validate.go", nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	literal := func(e ast.Expr) (string, bool) {
		lit, ok := e.(*ast.BasicLit)
		if !ok || lit.Kind != token.STRING {
			return "", false
		}
		s, err := strconv.Unquote(lit.Value)
		return s, err == nil
	}
	var messages []string
	ast.Inspect(file, func(n ast.Node) bool {
		switch n := n.(type) {
		case *ast.CallExpr:
			// add(path, code, message, args...) of a rule; add(code, message) of the switches
			if fn, ok := n.Fun.(*ast.Ident); ok && fn.Name == "add" {
				at := 1
				if len(n.Args) >= 3 {
					at = 2
				}
				if len(n.Args) > at {
					if s, ok := literal(n.Args[at]); ok {
						messages = append(messages, s)
					}
				}
			}
		case *ast.KeyValueExpr:
			if key, ok := n.Key.(*ast.Ident); ok && key.Name == "Message" {
				if s, ok := literal(n.Value); ok {
					messages = append(messages, s)
				}
			}
		}
		return true
	})
	if len(messages) == 0 {
		t.Fatal("found no messages in validate.go")
	}
	qml, err := os.ReadFile(filepath.Join(testkit.RepoRoot(), "qml/services/compositor/WindowRulesEditor.qml"))
	if err != nil {
		t.Fatal(err)
	}
	for _, message := range messages {
		quoted := strconv.Quote(message)
		if !strings.Contains(string(qml), "I18n.tr("+quoted+")") {
			t.Errorf("WindowRulesEditor.qml doesn't list I18n.tr(%s)", quoted)
		}
	}
}
