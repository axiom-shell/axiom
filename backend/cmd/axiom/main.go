// Command axiom is the axiom desktop's binary: the parent of the shell
// (`axiom run`), the owner of its config, and its command line.
package main

import (
	"os"

	"github.com/axiom-shell/axiom/backend/internal/cli"
)

func main() {
	os.Exit(cli.Main(os.Args[1:], &cli.Env{
		Stdin:  os.Stdin,
		Stdout: os.Stdout,
		Stderr: os.Stderr,
		Getenv: os.Getenv,
		Exec:   cli.ExecDev,
	}))
}
