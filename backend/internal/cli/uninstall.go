package cli

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"log/slog"
	"os"
	"path/filepath"
	"strings"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/command"
	"github.com/axiom-shell/axiom/backend/internal/daemon"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/footprint"
	"github.com/axiom-shell/axiom/backend/internal/secrets"
	"github.com/axiom-shell/axiom/backend/internal/session"
	"github.com/axiom-shell/axiom/backend/internal/tree"
	"github.com/axiom-shell/axiom/backend/internal/uninstall"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// `axiom uninstall`: takes axiom out of the user's home and session
// (docs/dev/backend/uninstall.md). It works on the files itself, so it runs
// without a daemon (install.sh --uninstall uses it), and with --stop quits
// the one that runs first.
func uninstallCommand() *Command {
	trail := []string{"axiom", "uninstall"}
	return &Command{
		Name:    "uninstall",
		Summary: "Take axiom out of your home and session, and say what it left",
		Help: `Gives back the compositor config axiom manages, undoes what axiom changed
outside its own folders (axiom footprint list), takes out the lines
install.sh added to your compositor config, deletes the files install.sh
put in your data folder, and removes axiom's own folders. It asks what to
keep (your settings; your notes, to-dos, themes, downloaded wallpapers and
calendars in ~/.local/share/axiom; saved passwords), each with a default of
keeping it; --purge-all gets rid of everything
instead. Your compositor configs and the backups it made (*.axiom-bak-*,
*.bak-<date>, *.axiom-backup-*) are never deleted: they are listed.
Lines it can't be sure are its own are left and listed to remove by hand.
The login screen is installed for the whole system and is removed first in
Settings → Login screen, or with axiom greeter-install uninstall as root.
--dry-run changes nothing. A package is removed with its package manager.`,
		Setup: func(fs *flag.FlagSet) Runner {
			dry := fs.Bool("dry-run", false, "print the plan and the answers' defaults, change nothing")
			yes := fs.Bool("yes", false, "take the defaults without asking")
			purge := fs.Bool("purge-all", false, "get rid of everything: settings, content, saved passwords (still asks about the system's defaults)")
			restore := fs.Bool("restore-system", false, "also put back the default apps and input method engines axiom set")
			stop := fs.Bool("stop", false, "quit axiom first, if it runs")
			noPortal := fs.Bool("no-portal-restart", false, "don't restart the screen-share portal")
			// No usage text: it isn't listed. The Settings button's answers,
			// in place of the questions
			answersFile := fs.String("answers", "", "")
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) > 0 {
					return usageError(trail, "takes no arguments")
				}
				o := uninstallOptions(ctx, e)
				plan, err := uninstall.Build(ctx, o)
				if err != nil {
					return err
				}
				if *answersFile != "" && (*purge || *restore) {
					return usageError(trail, "--answers carries the answers: don't combine it with --purge-all or --restore-system")
				}
				flags := uninstall.Flags{Yes: *yes, PurgeAll: *purge, RestoreSystem: *restore, NoPortalRestart: *noPortal}
				if *dry {
					defaults, _ := uninstall.Answer(uninstall.Flags{Yes: true, PurgeAll: *purge, RestoreSystem: *restore, NoPortalRestart: *noPortal}, plan.Counts, false, nil)
					return e.Output(map[string]any{"plan": plan, "answers": defaults}, func(w io.Writer) {
						printPlan(w, o, plan)
						fmt.Fprintf(w, "\nAnswers (the defaults): %s\n", describeAnswers(defaults))
					})
				}
				// Axiom running is said before any question is asked
				if len(plan.Running) > 0 && !*stop {
					return uninstall.RunningError(plan.Running)
				}
				var answers uninstall.Answers
				if *answersFile != "" {
					// (the daemon's file in the runtime folder is gone once read)
					defer removeAnswers(e, *answersFile)
					if answers, err = readAnswers(*answersFile); err != nil {
						return err
					}
				} else {
					ask := asker(e, o, plan)
					if answers, err = uninstall.Answer(flags, plan.Counts, e.isTTY(), ask); err != nil {
						return err
					}
				}
				if *stop {
					if err := uninstall.Stop(ctx, o); err != nil {
						return err
					}
				}
				report, err := uninstall.Run(ctx, o, plan, answers)
				if err != nil {
					return err
				}
				if packagedTree(e.Getenv) {
					report.Notes = append(report.Notes, "Remove the package too: sudo pacman -R axiom-shell (or axiom-shell-git)")
				}
				return e.Output(report, func(w io.Writer) { printReport(w, report) })
			}
		},
	}
}

// shutdownMethod is what quits a daemon (`axiom quit`'s)
const shutdownMethod = "daemon.shutdown"

// uninstallOptions are what an uninstall from the command line works on.
func uninstallOptions(ctx context.Context, e *Env) uninstall.Options {
	getenv := e.Getenv
	bin, _ := os.Executable()
	dirs := xdg.Resolve(getenv)
	log := slog.New(slog.NewTextHandler(e.Stderr, &slog.HandlerOptions{Level: slog.LevelWarn}))
	// The tree whose schema says where the integrations hook up: the
	// installed one, or $AXIOM_TREE (not the working directory's)
	treeDir, _ := tree.Find("", getenv, "/")
	dial := func(ctx context.Context) (*dbus.Conn, error) {
		addr, err := dbus.SessionAddress(getenv)
		if err != nil {
			return nil, err
		}
		return dbus.Dial(ctx, addr, dbus.Options{})
	}
	return uninstall.Options{
		Dirs: dirs, Getenv: getenv, Bin: bin, Log: log,
		Ledger: daemon.NewLedger(getenv, log, nil),
		Inferred: func(ctx context.Context) ([]footprint.Row, []footprint.Row) {
			return daemon.OfflineInferred(ctx, getenv, treeDir, bin)
		},
		DialBus: func(ctx context.Context) (session.Bus, func()) {
			conn, err := dial(ctx)
			if err != nil {
				return nil, nil
			}
			return conn, func() { conn.Close() }
		},
		Secrets: uninstall.SecretsSeam{
			Count: func(ctx context.Context) (int, error) {
				conn, err := dial(ctx)
				if err != nil {
					return 0, nil
				}
				defer conn.Close()
				return secrets.Count(ctx, conn)
			},
			ClearAll: func(ctx context.Context) error {
				// Only through the session bus this environment names, and
				// with its environment: a run for a scratch environment (a
				// test's) never reaches the keyring of another
				conn, err := dial(ctx)
				if err != nil {
					return nil
				}
				conn.Close()
				env := scopedEnv(getenv)
				return secrets.New(secrets.Options{
					StateDir: strings.TrimRight(dirs.State, "/"),
					Command:  func() command.Options { return command.Options{Env: env} },
				}).ClearAll(ctx)
			},
		},
		Shutdown: func(ctx context.Context, socket string) error {
			c, _, err := greet(ctx, e, socket)
			if err != nil {
				return err
			}
			defer c.Close()
			return c.Call(ctx, shutdownMethod, nil, nil)
		},
	}
}

// scopedEnv is the environment a program of the user's session gets, from
// what getenv says.
func scopedEnv(getenv func(string) string) []string {
	var env []string
	for _, k := range []string{"PATH", "HOME", "LANG", "XDG_RUNTIME_DIR", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_DATA_HOME",
		"XDG_CACHE_HOME", "DBUS_SESSION_BUS_ADDRESS", "WAYLAND_DISPLAY", "DISPLAY"} {
		if v := getenv(k); v != "" {
			env = append(env, k+"="+v)
		}
	}
	return env
}

// packagedTree: axiom is installed as a package (its tree has the marker
// the PKGBUILD writes), which the package manager removes.
func packagedTree(getenv func(string) string) bool {
	for _, dir := range tree.Installed(getenv) {
		if info, err := os.Stat(filepath.Join(dir, ".packaged")); err == nil && info.Mode().IsRegular() {
			return true
		}
	}
	return false
}

// answersPrefix names the answers file the daemon makes in the runtime folder
const answersPrefix = "axiom-uninstall-answers-"

// readAnswers reads the answers file of the Settings button: every one of
// the answers, none else (a file that's missing one or carries another is
// refused, so a half-written file never decides what is deleted).
func readAnswers(path string) (uninstall.Answers, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return uninstall.Answers{}, axerr.Wrap(axerr.BadRequest, err, "reading the answers")
	}
	var keys map[string]json.RawMessage
	if err := json.Unmarshal(data, &keys); err != nil {
		return uninstall.Answers{}, axerr.Wrap(axerr.BadRequest, err, "the answers in %s", path)
	}
	for _, k := range []string{"keepConfig", "keepUserContent", "keepSecrets", "undoInferred", "restoreSystem", "restartPortal"} {
		v, ok := keys[k]
		if !ok {
			return uninstall.Answers{}, axerr.New(axerr.BadRequest, "the answers in %s lack %s", path, k)
		}
		if t := bytes.TrimSpace(v); !bytes.Equal(t, []byte("true")) && !bytes.Equal(t, []byte("false")) {
			return uninstall.Answers{}, axerr.New(axerr.BadRequest, "the answers in %s: %s isn't true or false", path, k)
		}
	}
	a := uninstall.Answers{KeepConfig: true, KeepUserContent: true, KeepSecrets: true, UndoInferred: false, RestartPortal: true}
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&a); err != nil {
		return uninstall.Answers{}, axerr.Wrap(axerr.BadRequest, err, "the answers in %s", path)
	}
	return a, nil
}

// removeAnswers removes the daemon's answers file once it's been read (or
// refused): a file of the user's own is never touched.
func removeAnswers(e *Env, path string) {
	if rt := e.Getenv("XDG_RUNTIME_DIR"); rt != "" && filepath.Dir(path) == filepath.Clean(rt) && strings.HasPrefix(filepath.Base(path), answersPrefix) {
		os.Remove(path)
	}
}

// isTTY: the questions can be asked on the standard input.
func (e *Env) isTTY() bool {
	if e.TTY != nil {
		return e.TTY()
	}
	f, ok := e.Stdin.(*os.File)
	if !ok {
		return false
	}
	_, err := unix.IoctlGetTermios(int(f.Fd()), unix.TCGETS)
	return err == nil
}

// asker asks a question on the terminal, its default on Enter.
func asker(e *Env, o uninstall.Options, plan uninstall.Plan) func(q uninstall.Question, def bool) bool {
	// The questions go to stderr: --json's output stays one value
	in := bufio.NewReader(e.Stdin)
	home := e.Getenv("HOME")
	short := func(p string) string {
		if home != "" && strings.HasPrefix(p, home) {
			return "~" + strings.TrimPrefix(p, home)
		}
		return p
	}
	return func(q uninstall.Question, def bool) bool {
		var text string
		switch q.Field {
		case uninstall.FieldKeepConfig:
			text = "Keep your axiom settings (config.json, saved setups) in case you come back?"
		case uninstall.FieldKeepUserContent:
			text = fmt.Sprintf("Keep your notes, to-dos, themes, downloaded wallpapers and calendars in %s?", short(strings.TrimRight(o.Dirs.Data, "/")))
		case uninstall.FieldKeepSecrets:
			text = "Keep axiom's saved passwords and API keys?"
			if q.N > 0 {
				text = fmt.Sprintf("Keep axiom's saved passwords and API keys in your keyring (%d)?", q.N)
			}
		case uninstall.FieldUndoInferred:
			// The list first, then the question
			fmt.Fprintln(e.Stderr, "Changes axiom found without a record of making them:")
			for _, a := range plan.Actions {
				if a.Asks == uninstall.FieldUndoInferred {
					fmt.Fprintf(e.Stderr, "  %s %s\n", a.What, short(a.Path))
				}
			}
			text = fmt.Sprintf("Also undo %d changes axiom found without a record of making them?", q.N)
		case uninstall.FieldRestoreSystem:
			text = fmt.Sprintf("Also put back the default apps and input-method engines you set through axiom (%d)?", q.N)
		case uninstall.FieldRestartPortal:
			text = "Restart the screen-share portal now? A share running ends."
		}
		hint := "[Y/n]"
		if !def {
			hint = "[y/N]"
		}
		fmt.Fprintf(e.Stderr, "%s %s ", text, hint)
		line, _ := in.ReadString('\n')
		switch strings.ToLower(strings.TrimSpace(line)) {
		case "y", "yes":
			return true
		case "n", "no":
			return false
		}
		return def
	}
}

func describeAnswers(a uninstall.Answers) string {
	word := func(name string, v bool) string {
		if v {
			return name
		}
		return "no " + name
	}
	return strings.Join([]string{word("keep settings", a.KeepConfig), word("keep content", a.KeepUserContent), word("keep secrets", a.KeepSecrets),
		word("undo found changes", a.UndoInferred), word("restore system defaults", a.RestoreSystem), word("restart portal", a.RestartPortal)}, ", ")
}

func printPlan(w io.Writer, o uninstall.Options, p uninstall.Plan) {
	if len(p.Running) > 0 {
		fmt.Fprintf(w, "axiom runs on %s: quit it, or pass --stop\n\n", strings.Join(p.Running, ", "))
	}
	if p.Greeter != nil {
		fmt.Fprintf(w, "%s\n\n", p.Greeter.Text)
	}
	fmt.Fprintln(w, "axiom would:")
	for _, a := range p.Actions {
		line := "  " + a.What
		if a.Path != "" {
			line += " " + a.Path
		}
		if a.Detail != "" {
			line += " (" + a.Detail + ")"
		}
		if a.Asks != "" {
			line += "  [asks: " + a.Asks + "]"
		}
		fmt.Fprintln(w, line)
	}
	if len(p.Actions) == 0 {
		fmt.Fprintln(w, "  nothing: axiom changed nothing outside its own folders")
	}
	printManual(w, p.Manual)
	printBackups(w, p.Backups)
}

func printManual(w io.Writer, manual []uninstall.Manual) {
	if len(manual) == 0 {
		return
	}
	fmt.Fprintln(w, "\nLines to remove by hand (axiom isn't sure they are its own):")
	for _, m := range manual {
		if m.Line > 0 {
			fmt.Fprintf(w, "  %s:%d: %s\n    %s\n", m.File, m.Line, m.Text, m.Reason)
		} else {
			fmt.Fprintf(w, "  %s: %s\n", m.File, m.Reason)
		}
	}
}

func printBackups(w io.Writer, backups []string) {
	if len(backups) == 0 {
		return
	}
	fmt.Fprintln(w, "\nBackups kept:")
	for _, b := range backups {
		fmt.Fprintf(w, "  %s (%s)\n", b, humanSize(sizeOf(b)))
	}
	fmt.Fprintln(w, "These are copies of your files from before axiom changed them; delete them when you're sure.")
}

func printReport(w io.Writer, r uninstall.Report) {
	if r.Greeter != nil {
		fmt.Fprintf(w, "%s\n\n", r.Greeter.Text)
	}
	for _, i := range r.Done {
		fmt.Fprintf(w, "done: %s\n", itemLine(i))
	}
	if len(r.Left) > 0 {
		fmt.Fprintln(w, "\nLeft:")
		for _, i := range r.Left {
			fmt.Fprintf(w, "  %s\n", itemLine(i))
		}
	}
	printManual(w, r.Manual)
	printBackups(w, r.Backups)
	for _, n := range r.Notes {
		fmt.Fprintf(w, "\n%s\n", n)
	}
}

func itemLine(i uninstall.Item) string {
	s := i.What
	if i.Path != "" {
		s += " " + i.Path
	}
	if i.Detail != "" {
		s += " (" + i.Detail + ")"
	}
	return s
}

// sizeOf is a file's size, or a folder's (its files').
func sizeOf(path string) int64 {
	var n int64
	filepath.WalkDir(path, func(_ string, d fs.DirEntry, err error) error {
		if err == nil && !d.IsDir() {
			if info, err := d.Info(); err == nil {
				n += info.Size()
			}
		}
		return nil
	})
	return n
}

func humanSize(n int64) string {
	switch {
	case n >= 1<<20:
		return fmt.Sprintf("%.1f MB", float64(n)/(1<<20))
	case n >= 1<<10:
		return fmt.Sprintf("%.1f kB", float64(n)/(1<<10))
	}
	return fmt.Sprintf("%d bytes", n)
}
