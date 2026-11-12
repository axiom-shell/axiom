pragma Singleton
import QtQuick

// A bar widget showing several items (Lock keys' keys, Markets' symbols, …)
// drawn one box per item (its Boxes: One per item): its section's entry
// expanded into one entry per item, each hosted as a widget of its own
// (BarWidgetHost), so each takes the bar's style, pill, split and place in
// a run. The items come from config only (BarsConfig.boxItems), never from
// live values.
QtObject {
  id: root

  // The items of `options` ({ item: option }) whose boolean option is on in
  // `properties`, in `options`' order
  function fromOptions(options, properties) {
    return Object.keys(options ?? {}).filter(item => properties?.[options[item]] === true);
  }

  // A section's entries ({ configIndex, … }) with each one that has more
  // than one item (`itemsOf(entry)`, [] for a widget drawn whole) expanded
  // into one per item: the same entry with its item as `box`. Its
  // `configIndex` stays the entry's: the bar editor still sees one widget.
  function expand(entries, itemsOf) {
    return entries.reduce((out, entry) => {
      const items = itemsOf(entry) ?? [];
      if (items.length < 2)
        return out.concat([entry]);
      return out.concat(items.map(item => Object.assign({}, entry, {
          "box": String(item)
        })));
    }, []);
  }
}
