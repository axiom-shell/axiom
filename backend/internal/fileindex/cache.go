package fileindex

import "github.com/axiom-shell/axiom/backend/internal/fsx"

// writeCache writes the index's cache atomically, readable by the user
// alone: it names every file under the roots.
func writeCache(path string, data []byte) error {
	return fsx.WriteFile(path, data, 0o600)
}
