package cli

import (
	"slices"
	"testing"
)

func TestGreeterEnvDropsInheritedAxiomValues(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name    string
		environ []string
		set     map[string]string
		want    []string
	}{
		{
			name: "a session axiom's values never reach the greeter",
			environ: []string{
				"HOME=/h", "AXIOM_SOCKET=/s", "AXIOM_DAEMON_PID=1", "AXIOM_INCOMPATIBLE=x",
				"AXIOM_LOCK_ON_START=1", "AXIOM_REEXEC=3", "AXIOM_SOMETHING_NEW=1", "PATH=/bin",
			},
			set:  map[string]string{"AXIOM_GREETER": "1"},
			want: []string{"HOME=/h", "PATH=/bin", "AXIOM_GREETER=1"},
		},
		{
			name:    "its own values replace the inherited ones",
			environ: []string{"AXIOM_BIN=/old", "AXIOM_TREE=/old", "AXIOM_CONFIG=/old"},
			set:     map[string]string{"AXIOM_BIN": "/new", "AXIOM_TREE": "/t"},
			want:    []string{"AXIOM_BIN=/new", "AXIOM_TREE=/t"},
		},
		{
			name:    "the knobs for looking at it from a session stay",
			environ: []string{"AXIOM_GREETER_WINDOWED=1", "AXIOM_COMPOSITOR=none", "AXIOM_COMPOSITOR_OFF=blur", "AXIOM_GREETER_SAFE=1"},
			want:    []string{"AXIOM_GREETER_WINDOWED=1", "AXIOM_COMPOSITOR=none", "AXIOM_COMPOSITOR_OFF=blur"},
		},
		{
			name:    "a value that only starts like one is kept",
			environ: []string{"AXIOMX=1", "MY_AXIOM_SOCKET=1"},
			want:    []string{"AXIOMX=1", "MY_AXIOM_SOCKET=1"},
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			got := greeterEnv(c.environ, c.set)
			slices.Sort(got)
			want := slices.Clone(c.want)
			slices.Sort(want)
			if !slices.Equal(got, want) {
				t.Errorf("greeterEnv = %q, want %q", got, want)
			}
		})
	}
}
