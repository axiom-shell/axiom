package daemon

import (
	"context"

	"github.com/axiom-shell/axiom/backend/internal/chat"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// chatPart: ChatManager's requests to the providers, answered by package
// chat, which reads the keys itself (the shell's environment, then
// package secrets).
func (d *Daemon) chatPart() part {
	return part{name: "chat", methods: d.chatMethods}
}

func (d *Daemon) chatMethods(reg *rpc.Registry) {
	s := chat.New(chat.Options{
		Secrets: d.secretStore("chat"),
		Command: d.commandOptions,
		Log:     d.opts.Log.With("part", "chat"),
	})
	type stopParams struct {
		ID string `json:"id"`
	}
	// The reply streams as chat.delta pushes to this connection; the
	// result comes when it ends
	rpc.Handle(reg, "chat.send", func(ctx context.Context, c *rpc.Conn, p chat.SendRequest) (chat.SendResult, error) {
		return s.Send(ctx, p, func(d chat.Delta) { c.Notify(pushChatDelta.Method, d) })
	})
	rpc.Handle(reg, "chat.stop", func(ctx context.Context, c *rpc.Conn, p stopParams) (struct{}, error) {
		s.Stop(p.ID)
		return struct{}{}, nil
	})
	rpc.Handle(reg, "chat.models", func(ctx context.Context, c *rpc.Conn, p chat.ModelsRequest) (chat.ModelsResult, error) {
		return s.Models(ctx, p)
	})
}
