package daemon

import (
	"log/slog"
	"slices"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/topics"
)

// Contract is the daemon's side of the protocol as it goes on the wire:
// every method's params and result, every push's params, and every polled
// topic's request and state (pushed as `<name>.state`).
// backend/tools/rpcshapes prints it for scripts/gen_docs.py.
type Contract struct {
	Methods []rpc.MethodShape `json:"methods"`
	Pushes  []rpc.PushShape   `json:"pushes"`
	Topics  []TopicShape      `json:"topics"`
}

// TopicShape is one polled topic: what a subscribe asks besides its
// interval, and the state it pushes.
type TopicShape struct {
	Name    string    `json:"name"`
	Request rpc.Shape `json:"request"`
	State   rpc.Shape `json:"state"`
}

// pushShapes are every push declared in methods.go, for Contract
// (scripts/gen_docs.py fails on a declared push missing here).
func pushShapes() []rpc.PushShape {
	return []rpc.PushShape{
		pushConfigChanged.Shape(), pushConfigState.Shape(), pushSchemaChanged.Shape(), pushSchemaError.Shape(),
		pushSavedState.Shape(),
		pushDaemonState.Shape(), pushDevState.Shape(), pushDaemonClosing.Shape(),
		pushCompositorState.Shape(), pushCompositorApplied.Shape(), pushCompositorNotify.Shape(), pushCompositorBindsMerged.Shape(),
		pushIdleState.Shape(),
		pushWaylandState.Shape(), pushNightLightState.Shape(),
		pushClipboardState.Shape(),
		pushExecOutputs.Shape(),
		pushChatDelta.Shape(),
		pushFileChanged.Shape(),
		pushNiriStarted.Shape(), pushNiriEvent.Shape(),
	}
}

// methodSets are every part's methods (Run's parts, which also configure
// and run things, so Contract can't build them). A test checks a running
// daemon registers exactly these.
func (d *Daemon) methodSets() []func(*rpc.Registry) {
	return []func(*rpc.Registry){
		d.coreMethods, d.configMethods, d.ipcMethods, d.sharingMethods,
		func(reg *rpc.Registry) { d.compositorMethods(reg, d.compositor) },
		d.compositorSocketMethods, d.topicsPart().methods, d.toolsMethods, d.execMethods, d.filesMethods, d.calendarMethods, d.chatMethods, d.secretsMethods, d.themeMethods, d.hookupMethods, d.selfUpdateMethods, d.greeterInstallMethods, d.cursorMethods, d.brightnessPart().methods, d.idleMethods, d.waylandMethods, d.clipboardMethods, d.dev.methods,
	}
}

// greeterOnlyMethods are the methods the greeter's axiom serves and the
// session's doesn't (greeterRegistry), which the contract lists too: the
// shell calls them in greeter mode.
func greeterOnlyMethods(reg *rpc.Registry, getenv func(string) string, schema func() any) {
	inputHandlers(reg, getenv, schema)
}

// BuildContract builds the daemon's registry without starting anything
// (registering only stores closures), with the greeter's own methods, and
// reports its shapes.
func BuildContract() Contract {
	d := &Daemon{opts: Options{Getenv: func(string) string { return "" }, Log: slog.New(slog.DiscardHandler)}}
	d.topics = topics.New(topics.Options{Log: d.opts.Log})
	d.dev = newDevMode(d, false)
	reg := rpc.NewRegistry()
	for _, methods := range d.methodSets() {
		methods(reg)
	}
	greeterOnlyMethods(reg, d.opts.Getenv, func() any { return nil })
	c := Contract{Methods: reg.Shapes(), Pushes: pushShapes()}
	slices.SortFunc(c.Pushes, func(a, b rpc.PushShape) int { return strings.Compare(a.Method, b.Method) })
	for _, src := range d.sources() {
		c.Topics = append(c.Topics, TopicShape{Name: src.Name, Request: rpc.ShapeOf(src.Request), State: rpc.ShapeOf(src.State)})
	}
	slices.SortFunc(c.Topics, func(a, b TopicShape) int { return strings.Compare(a.Name, b.Name) })
	return c
}
