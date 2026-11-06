package daemon

import (
	"context"

	"github.com/axiom-shell/axiom/backend/internal/camera"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// newCamera is the processes holding a camera's device open
// (PrivacyManager): apps reading it themselves, not through PipeWire.
func (d *Daemon) newCamera() {
	d.camera = camera.New(camera.Options{
		OnChange: func(st camera.State) {
			if d.server != nil {
				pushCameraState.Send(d.server, st, subscribedTo(topicCamera))
			}
		},
		Log: d.opts.Log.With("part", "camera"),
	})
}

// cameraPart: the camera devices, watched while the daemon runs.
func (d *Daemon) cameraPart() part {
	return part{
		name:    "camera",
		methods: d.cameraMethods,
		run:     d.camera.Run,
	}
}

func (d *Daemon) cameraMethods(reg *rpc.Registry) {
	rpc.Handle(reg, "camera.get", func(ctx context.Context, c *rpc.Conn, _ struct{}) (camera.State, error) {
		return d.camera.State(), nil
	})
}
