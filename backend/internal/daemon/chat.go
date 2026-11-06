package daemon

import (
	"context"
	"strings"

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
	})
	type stopParams struct {
		ID string `json:"id"`
	}
	// The reply streams as chat.delta pushes to this connection; the
	// result comes when it ends
	rpc.Handle(reg, "chat.send", func(ctx context.Context, c *rpc.Conn, p chat.SendRequest) (chat.SendResult, error) {
		emit, flush := gatherDeltas(c)
		defer flush()
		return s.Send(ctx, p, emit)
	})
	rpc.Handle(reg, "chat.stop", func(ctx context.Context, c *rpc.Conn, p stopParams) (struct{}, error) {
		s.Stop(p.ID)
		return struct{}{}, nil
	})
	rpc.Handle(reg, "chat.models", func(ctx context.Context, c *rpc.Conn, p chat.ModelsRequest) (chat.ModelsResult, error) {
		return s.Models(ctx, p)
	})
}

// gatherDeltas is chat.send's emit: a piece of the reply is pushed at once
// while the shell keeps up, and gathered with the pieces after it while
// the connection's queue is backlogged, so a fast reply to a shell that
// stopped reading never fills the queue (which drops the connection).
// flush pushes what's held; it runs before chat.send answers.
func gatherDeltas(c *rpc.Conn) (emit func(chat.Delta), flush func()) {
	var held []chat.Delta // the last one's text is in last
	var last strings.Builder
	flush = func() {
		if len(held) == 0 {
			return
		}
		held[len(held)-1].Text = last.String()
		for _, d := range held {
			c.Notify(pushChatDelta.Method, d)
		}
		held = held[:0]
		last.Reset()
	}
	emit = func(d chat.Delta) {
		if n := len(held); n == 0 || held[n-1].Kind != d.Kind {
			if n > 0 {
				held[n-1].Text = last.String()
			}
			last.Reset()
			held = append(held, d)
		}
		last.WriteString(d.Text)
		if !c.Backlogged() {
			flush()
		}
	}
	return emit, flush
}
