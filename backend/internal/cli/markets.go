package cli

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"math"
	"strconv"
	"strings"
	"text/tabwriter"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/markets"
)

// `axiom markets`: the Markets watchlist from the command line (a script
// keeping a holding up to date, adding a symbol, setting an alert) and its
// prices. Edits are config ops on Markets.symbols, through the daemon (or
// the file, offline) like `config set`; prices come from the daemon's
// `markets` cache.
func marketsCommand() *Command {
	return &Command{
		Name:    "markets",
		Summary: "The stock and crypto watchlist: prices, holdings, alerts, symbols",
		Subs: []*Command{
			marketsListCommand(),
			marketsAddCommand(),
			marketsRemoveCommand(),
			marketsHoldCommand(),
			marketsAlertCommand(),
			marketsMoveCommand(),
			marketsSearchCommand(),
			marketsRefreshCommand(),
		},
	}
}

var symbolsPath = config.Path{{Key: "Markets"}, {Key: "symbols"}}

// watchlist is the config's watchlist and settings, as `current` reads
// them.
type watchlist struct {
	list            *jsonx.Array
	baseCurrency    string
	pauseWhenClosed bool
}

func readWatchlist(ctx context.Context, e *Env) (watchlist, error) {
	cfg, _, _, _, err := current(ctx, e, "")
	if err != nil {
		return watchlist{}, err
	}
	w := watchlist{list: &jsonx.Array{}}
	if v, ok := config.Lookup(cfg, symbolsPath); ok {
		if list, ok := v.(*jsonx.Array); ok {
			w.list = list
		}
	}
	if v, ok := config.Lookup(cfg, config.Path{{Key: "Markets"}, {Key: "baseCurrency"}}); ok {
		w.baseCurrency, _ = v.(string)
	}
	if v, ok := config.Lookup(cfg, config.Path{{Key: "Markets"}, {Key: "pauseWhenClosed"}}); ok {
		w.pauseWhenClosed = v == true
	}
	return w, nil
}

// itemPath is the path of item's key (none: the item itself).
func itemPath(item *jsonx.Object, key string) config.Path {
	p := append(append(config.Path{}, symbolsPath...), config.Segment{ID: str(item.Value("id"))})
	if key != "" {
		p = append(p, config.Segment{Key: key})
	}
	return p
}

func str(v any) string {
	s, _ := v.(string)
	return s
}

// edited applies ops, then says what changed (text only: --json prints
// the write's answer).
func edited(ctx context.Context, e *Env, ops []config.Op, said string) error {
	if err := applyOps(ctx, e, "", ops, false); err != nil {
		return err
	}
	if !e.Globals.JSON {
		fmt.Fprintln(e.Stdout, said)
	}
	return nil
}

func nameOf(item *jsonx.Object) string {
	if label := str(item.Value("label")); label != "" {
		return label
	}
	return str(item.Value("symbol"))
}

func marketsListCommand() *Command {
	trail := []string{"axiom", "markets", "list"}
	return &Command{
		Name:    "list",
		Summary: "Show the watchlist with its prices, holdings and alerts",
		Help: `Prices come from the daemon (what's due is fetched first); offline, or
with --no-prices, only the watchlist is shown. With --json: the items, each
with its "quote" (null without one), and the portfolio's "fx" rates.`,
		Setup: func(fs *flag.FlagSet) Runner {
			noPrices := fs.Bool("no-prices", false, "show the watchlist alone")
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) > 0 {
					return usageError(trail, "takes no arguments")
				}
				w, err := readWatchlist(ctx, e)
				if err != nil {
					return err
				}
				var st *markets.State
				if !*noPrices && !e.Globals.Offline {
					st = &markets.State{}
					if err := call(ctx, e, "markets.quotes", markets.RequestFor(w.list, w.baseCurrency, w.pauseWhenClosed), st); err != nil {
						if axerr.KindOf(err) != axerr.Unavailable {
							return err
						}
						st = nil
					}
				}
				type row struct {
					Item  json.RawMessage `json:"item"`
					Quote *markets.Quote  `json:"quote"`
					obj   *jsonx.Object
				}
				rows := []row{}
				for _, v := range w.list.Items {
					item, ok := v.(*jsonx.Object)
					if !ok {
						continue
					}
					r := row{Item: jsonx.MarshalCompact(item), obj: item}
					if st != nil {
						r.Quote = st.Quotes[markets.ItemKey(item)]
					}
					rows = append(rows, r)
				}
				out := map[string]any{"items": rows, "baseCurrency": w.baseCurrency}
				if st != nil {
					out["fx"] = st.FX
				}
				return e.Output(out, func(wr io.Writer) {
					if len(rows) == 0 {
						fmt.Fprintln(wr, "The watchlist is empty: axiom markets add SYMBOL")
						return
					}
					tw := tabwriter.NewWriter(wr, 0, 0, 2, ' ', 0)
					fmt.Fprintln(tw, "ID\tSYMBOL\tNAME\tPRICE\tCHANGE\tHOLDING\tVALUE\tALERTS")
					for _, r := range rows {
						item := r.obj
						qty := markets.Num(item.Value("quantity"))
						price, change, value := "—", "", ""
						if q := r.Quote; q != nil && q.Error == "" {
							price = formatPrice(q.Price, q.Currency)
							change = fmt.Sprintf("%+.2f%%", q.ChangePercent)
							if q.Stale {
								change += " (old)"
							}
							if qty > 0 {
								value = formatPrice(qty*q.Price, q.Currency)
							}
						} else if q != nil {
							change = q.Error
						}
						holding := ""
						if qty > 0 {
							holding = strconv.FormatFloat(qty, 'f', -1, 64)
						}
						fmt.Fprintf(tw, "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", str(item.Value("id")), str(item.Value("symbol")), nameOf(item), price, change, holding, value, alerts(item))
					}
					tw.Flush()
				})
			}
		},
	}
}

func alerts(item *jsonx.Object) string {
	var out []string
	if v := markets.Num(item.Value("alertAbove")); v > 0 {
		out = append(out, "above "+strconv.FormatFloat(v, 'f', -1, 64))
	}
	if v := markets.Num(item.Value("alertBelow")); v > 0 {
		out = append(out, "below "+strconv.FormatFloat(v, 'f', -1, 64))
	}
	return strings.Join(out, ", ")
}

// formatPrice: two decimals from 1, four from 0.01, else four
// significant digits, then the currency.
func formatPrice(v float64, currency string) string {
	places := 2
	if a := math.Abs(v); a > 0 && a < 1 {
		places = 4
		if a < 0.01 {
			places = min(12, 3-int(math.Floor(math.Log10(a))))
		}
	}
	s := strconv.FormatFloat(v, 'f', places, 64)
	if currency == "" {
		return s
	}
	return s + " " + currency
}

func marketsAddCommand() *Command {
	trail := []string{"axiom", "markets", "add"}
	return &Command{
		Name:    "add",
		Summary: "Add a symbol to the watchlist",
		Args:    "SYMBOL",
		Help: `SYMBOL is Yahoo Finance's (AAPL, ^GSPC, BTC-USD, EURUSD=X), or with
--coingecko CoinGecko's coin id (bitcoin). axiom markets search finds them.`,
		Setup: func(fs *flag.FlagSet) Runner {
			gecko := fs.Bool("coingecko", false, "SYMBOL is a CoinGecko coin id")
			label := fs.String("label", "", "shown instead of the symbol")
			quantity := fs.String("hold", "", "how many you own")
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) != 1 || strings.TrimSpace(args[0]) == "" {
					return usageError(trail, "takes one symbol")
				}
				symbol := strings.TrimSpace(args[0])
				source := markets.SourceYahoo
				if *gecko {
					source = markets.SourceCoinGecko
				}
				w, err := readWatchlist(ctx, e)
				if err != nil {
					return err
				}
				if markets.Has(w.list, symbol, source) {
					return axerr.New(axerr.Conflict, "%s is already on the watchlist", symbol)
				}
				item := jsonx.NewObject()
				id := markets.FreeID(w.list, symbol)
				item.Set("id", id)
				item.Set("symbol", symbol)
				item.Set("source", source)
				item.Set("label", *label)
				if *quantity != "" {
					q, err := markets.Amount(*quantity, 0)
					if err != nil {
						return err
					}
					item.Set("quantity", q)
				}
				p := append(append(config.Path{}, symbolsPath...), config.Segment{ID: id})
				return edited(ctx, e, []config.Op{config.SetValue(p, item)}, fmt.Sprintf("Added %s (id %s)", symbol, id))
			}
		},
	}
}

func marketsRemoveCommand() *Command {
	trail := []string{"axiom", "markets", "remove"}
	return &Command{
		Name:    "remove",
		Summary: "Take a symbol off the watchlist",
		Args:    "SYMBOL",
		Help:    "SYMBOL names an item by its id, symbol or label.",
		Setup: func(fs *flag.FlagSet) Runner {
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) != 1 {
					return usageError(trail, "takes one symbol")
				}
				w, err := readWatchlist(ctx, e)
				if err != nil {
					return err
				}
				item, err := markets.Find(w.list, args[0])
				if err != nil {
					return err
				}
				return edited(ctx, e, []config.Op{{Op: "delete", Path: itemPath(item, "")}}, "Removed "+nameOf(item))
			}
		},
	}
}

func marketsHoldCommand() *Command {
	trail := []string{"axiom", "markets", "hold"}
	return &Command{
		Name:    "hold",
		Summary: "Set how many of a symbol you own (and what you paid)",
		Args:    "SYMBOL AMOUNT",
		Help: `AMOUNT sets the holding (12), or adds to it (+2) or takes from it (-0.5);
0 holds none. --cost sets the average price paid for each, in the symbol's
currency (0 leaves the total gain out). A relative amount fails, rather than
being lost, when the holding changed while it was read.`,
		Setup: func(fs *flag.FlagSet) Runner {
			cost := fs.String("cost", "", "the average price paid for each")
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) != 2 {
					return usageError(trail, "takes a symbol and an amount")
				}
				w, err := readWatchlist(ctx, e)
				if err != nil {
					return err
				}
				item, err := markets.Find(w.list, args[0])
				if err != nil {
					return err
				}
				currentRaw, has := item.Get("quantity")
				current := markets.Num(currentRaw)
				q, err := markets.Amount(args[1], current)
				if err != nil {
					return err
				}
				op := config.SetValue(itemPath(item, "quantity"), q)
				if has && strings.ContainsAny(args[1][:1], "+-") {
					op = op.WithBase(currentRaw)
				}
				ops := []config.Op{op}
				said := fmt.Sprintf("%s: %s held", nameOf(item), strconv.FormatFloat(q, 'f', -1, 64))
				if *cost != "" {
					c, err := markets.Amount(*cost, 0)
					if err != nil {
						return err
					}
					ops = append(ops, config.SetValue(itemPath(item, "averageCost"), c))
					said += fmt.Sprintf(" at %s each", strconv.FormatFloat(c, 'f', -1, 64))
				}
				return edited(ctx, e, ops, said)
			}
		},
	}
}

func marketsAlertCommand() *Command {
	trail := []string{"axiom", "markets", "alert"}
	return &Command{
		Name:    "alert",
		Summary: "Set or clear a symbol's price alerts",
		Args:    "SYMBOL",
		Help: `--above and --below set the prices crossing which notifies once (0 clears
one); --clear clears both. The alerts notify only while Markets.alerts is on.`,
		Setup: func(fs *flag.FlagSet) Runner {
			above := fs.String("above", "", "notify when the price rises to this")
			below := fs.String("below", "", "notify when the price falls to this")
			clearBoth := fs.Bool("clear", false, "clear both alerts")
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) != 1 || (*above == "" && *below == "" && !*clearBoth) {
					return usageError(trail, "takes a symbol and --above, --below or --clear")
				}
				w, err := readWatchlist(ctx, e)
				if err != nil {
					return err
				}
				item, err := markets.Find(w.list, args[0])
				if err != nil {
					return err
				}
				set := map[string]string{"alertAbove": *above, "alertBelow": *below}
				if *clearBoth {
					set = map[string]string{"alertAbove": "0", "alertBelow": "0"}
				}
				var ops []config.Op
				for _, key := range []string{"alertAbove", "alertBelow"} {
					if set[key] == "" {
						continue
					}
					v, err := strconv.ParseFloat(set[key], 64)
					if err != nil || v < 0 || v != v {
						return axerr.New(axerr.BadRequest, "%q isn't a price", set[key])
					}
					ops = append(ops, config.SetValue(itemPath(item, key), v))
				}
				// Read back as written: the item with these alerts
				shown := jsonx.Clone(item).(*jsonx.Object)
				for _, op := range ops {
					shown.Set(op.Path[len(op.Path)-1].Key, op.Value.V)
				}
				said := nameOf(item) + ": no alerts"
				if a := alerts(shown); a != "" {
					said = nameOf(item) + ": alerts " + a
				}
				return edited(ctx, e, ops, said)
			}
		},
	}
}

func marketsMoveCommand() *Command {
	trail := []string{"axiom", "markets", "move"}
	return &Command{
		Name:    "move",
		Summary: "Move a symbol to another place in the watchlist",
		Args:    "SYMBOL POSITION",
		Help:    "POSITION counts from 1 (the first); past the end is the last.",
		Setup: func(fs *flag.FlagSet) Runner {
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) != 2 {
					return usageError(trail, "takes a symbol and a position")
				}
				pos, err := strconv.Atoi(args[1])
				if err != nil || pos < 1 {
					return usageError(trail, "POSITION is a number from 1")
				}
				w, err := readWatchlist(ctx, e)
				if err != nil {
					return err
				}
				item, err := markets.Find(w.list, args[0])
				if err != nil {
					return err
				}
				id := str(item.Value("id"))
				var ids []any
				for _, v := range w.list.Items {
					if o, ok := v.(*jsonx.Object); ok && str(o.Value("id")) != id {
						ids = append(ids, str(o.Value("id")))
					}
				}
				at := min(pos-1, len(ids))
				ids = append(ids[:at], append([]any{id}, ids[at:]...)...)
				op := config.Op{Op: "order", Path: symbolsPath}
				op.Value.V, op.Value.Set = &jsonx.Array{Items: ids}, true
				return edited(ctx, e, []config.Op{op}, fmt.Sprintf("Moved %s to %d", nameOf(item), at+1))
			}
		},
	}
}

func marketsSearchCommand() *Command {
	trail := []string{"axiom", "markets", "search"}
	return &Command{
		Name:    "search",
		Summary: "Find symbols to watch (Yahoo Finance and CoinGecko)",
		Args:    "TEXT…",
		Setup: func(fs *flag.FlagSet) Runner {
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) == 0 {
					return usageError(trail, "takes what to search for")
				}
				var res markets.SearchResult
				if err := call(ctx, e, "markets.search", markets.SearchRequest{Query: strings.Join(args, " ")}, &res); err != nil {
					return err
				}
				return e.Output(res, func(w io.Writer) {
					tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
					fmt.Fprintln(tw, "SYMBOL\tKIND\tNAME\tEXCHANGE\tADD WITH")
					for _, m := range res.Matches {
						add := "axiom markets add " + m.Symbol
						if m.Source == markets.SourceCoinGecko {
							add = "axiom markets add --coingecko " + m.Symbol
						}
						fmt.Fprintf(tw, "%s\t%s\t%s\t%s\t%s\n", m.Display, m.Kind, m.Name, m.Exchange, add)
					}
					tw.Flush()
					if res.Error != "" {
						fmt.Fprintln(w, "(partly: "+res.Error+")")
					}
				})
			}
		},
	}
}

func marketsRefreshCommand() *Command {
	return &Command{
		Name:    "refresh",
		Summary: "Fetch every watched price now (while the shell shows them)",
		Setup: func(fs *flag.FlagSet) Runner {
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) > 0 {
					return usageError([]string{"axiom", "markets", "refresh"}, "takes no arguments")
				}
				return call(ctx, e, "markets.refresh", struct{}{}, nil)
			}
		},
	}
}
