package fileindex

import (
	"io"

	"github.com/axiom-shell/axiom/backend/internal/filesearch"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
)

// writeCache streams the index's cache to path atomically, readable by
// the user alone (it names every file under the roots), without fsync: a
// torn cache fails its CRC and the index is built again.
func writeCache(path string, ix *filesearch.Index, key uint64) error {
	return fsx.WriteCache(path, 0o600, func(w io.Writer) error { return ix.Encode(w, key) })
}
