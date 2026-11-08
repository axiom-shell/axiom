package cli

import (
	"context"
	"flag"

	"github.com/axiom-shell/axiom/backend/internal/fileindex"
	"github.com/axiom-shell/axiom/backend/internal/thumbnail"
)

// The file search's children, which the daemon runs as itself
// (/proc/self/exe): their requests on stdin, never in argv.

func indexCrawlCommand() *Command {
	return &Command{
		Name:    fileindex.ChildCommand,
		Summary: "Crawl folders for the launcher's file index (the daemon runs it)",
		Hidden:  true,
		Help: `The daemon's crawl child: every thread goes to SCHED_IDLE and the
idle I/O class first, then it reads one JSON request on stdin (the roots,
excludes, and the folders to walk or check) and streams each folder it
reads to stdout in the binary frames the daemon applies.`,
		Setup: func(fs *flag.FlagSet) Runner {
			return func(ctx context.Context, e *Env, args []string) error {
				return fileindex.RunChild(ctx, e.Stdin, e.Stdout)
			}
		},
	}
}

func thumbnailCommand() *Command {
	return &Command{
		Name:    thumbnail.ChildCommand,
		Summary: "Make one image thumbnail for the launcher (the daemon runs it)",
		Hidden:  true,
		Help: `The daemon's thumbnail child: at nice 10 and the lowest best-effort
I/O priority, it reads one JSON request on stdin and writes the
thumbnail the freedesktop spec names. A file it can't decode exits as
refused (4), which the daemon records as failed.`,
		Setup: func(fs *flag.FlagSet) Runner {
			return func(ctx context.Context, e *Env, args []string) error {
				return thumbnail.RunChild(ctx, e.Stdin)
			}
		},
	}
}
