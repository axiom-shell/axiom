// Command rpcshapes prints the daemon's side of the shell–daemon protocol
// as JSON: every method's params and result, every push's params and every
// polled topic's request and state, as field trees (daemon.BuildContract,
// which starts nothing). scripts/generate.sh writes it to
// docs/dev/generated/rpc-shapes.json for scripts/gen_docs.py.
package main

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/axiom-shell/axiom/backend/internal/daemon"
)

func main() {
	if len(os.Args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: rpcshapes (prints JSON on stdout)")
		os.Exit(2)
	}
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", " ")
	if err := enc.Encode(daemon.BuildContract()); err != nil {
		fmt.Fprintln(os.Stderr, "rpcshapes:", err)
		os.Exit(1)
	}
}
