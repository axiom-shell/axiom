package cli

import (
	"flag"
	"fmt"
	"io"
	"strings"
	"text/tabwriter"
)

// writeHelp prints a command's usage: its synopsis and help, then its
// subcommands or its flags.
func writeHelp(w io.Writer, cmd *Command, trail []string) {
	name := strings.Join(trail, " ")
	if cmd.Setup == nil {
		fmt.Fprintf(w, "usage: %s <command> [flags]\n", name)
	} else {
		fmt.Fprintf(w, "usage: %s [flags] %s\n", name, cmd.Args)
	}
	if cmd.Summary != "" {
		fmt.Fprintf(w, "\n%s\n", cmd.Summary)
	}
	if cmd.Help != "" {
		fmt.Fprintf(w, "\n%s\n", strings.TrimSpace(cmd.Help))
	}
	if cmd.Setup == nil {
		fmt.Fprintln(w, "\ncommands:")
		tw := tabwriter.NewWriter(w, 0, 4, 2, ' ', 0)
		for _, s := range cmd.Subs {
			if !s.Hidden {
				fmt.Fprintf(tw, "  %s\t%s\n", s.Name, s.Summary)
			}
		}
		tw.Flush()
		fmt.Fprintf(w, "\nRun `%s <command> --help` for a command's flags.\n", name)
		return
	}
	fs := flag.NewFlagSet(name, flag.ContinueOnError)
	cmd.Setup(fs)
	addGlobals(fs, &Globals{})
	fmt.Fprintln(w, "\nflags:")
	tw := tabwriter.NewWriter(w, 0, 4, 2, ' ', 0)
	fs.VisitAll(func(f *flag.Flag) {
		arg := ""
		if _, isBool := f.Value.(interface{ IsBoolFlag() bool }); !isBool {
			arg = " " + valueName(f)
		}
		dash := "--"
		if len(f.Name) == 1 {
			dash = "-" // a short flag (-f, -o), as it's usually typed
		}
		fmt.Fprintf(tw, "  %s%s%s\t%s\n", dash, f.Name, arg, f.Usage)
	})
	tw.Flush()
}

func valueName(f *flag.Flag) string {
	name, _ := flag.UnquoteUsage(f)
	if name == "" {
		return "VALUE"
	}
	return strings.ToUpper(name)
}
