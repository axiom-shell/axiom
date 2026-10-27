package daemon

import (
	"context"

	"github.com/axiom-shell/axiom/backend/internal/chat"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// chatPart: ChatManager's requests to the providers and SecretsManager's
// chat key statuses, answered by package chat, which reads the keys
// itself (the shell's environment, the keyring, secrets.json).
func (d *Daemon) chatPart() part {
	return part{name: "chat", methods: d.chatMethods}
}

func (d *Daemon) chatMethods(reg *rpc.Registry) {
	s := chat.New(chat.Options{
		StateDir: d.dirs.State,
		Command:  d.commandOptions,
		Log:      d.opts.Log.With("part", "chat"),
	})
	rpc.Handle(reg, "chat.models", func(ctx context.Context, c *rpc.Conn, p chat.ModelsRequest) (chat.ModelsResult, error) {
		return s.Models(ctx, p)
	})
	rpc.Handle(reg, "secrets.status", func(ctx context.Context, c *rpc.Conn, p chat.StatusRequest) (chat.StatusResult, error) {
		return s.Status(ctx, p)
	})
}
