pragma Singleton
import QtQuick

// Pure helpers for searching lists by typed text: the launcher's fuzzy
// score, frecency from a { count, last } use record (Utils.recordUse) and
// whether text reads as math for the calculator. No file access, processes
// or services.
QtObject {
  id: root

  // How well `text` matches `q` (lowercase): 100 exact, 80 prefix, 65 at a
  // word start, 50 inside, 5-30 for the letters in order (closer is
  // higher), 0 for no match
  function score(text, q) {
    if (!text || !q)
      return 0;
    const t = text.toLowerCase();
    if (t === q)
      return 100;
    if (t.startsWith(q))
      return 80;
    const at = t.indexOf(q);
    if (at > 0)
      return /[\s\-_./]/.test(t.charAt(at - 1)) ? 65 : 50;
    if (q.length < 2)
      return 0;
    let matched = 0, first = -1, last = 0;
    for (let i = 0; i < t.length && matched < q.length; i++) {
      if (t[i] === q[matched]) {
        if (first < 0)
          first = i;
        last = i;
        matched++;
      }
    }
    if (matched < q.length)
      return 0;
    return Math.max(5, 30 - 2 * (last - first + 1 - q.length));
  }

  // The icons (the catalog's lowercase [name, "search words"], most popular
  // first: IconManager) best matching `query`, at most `limit` names: by
  // name (the query's spaces read as underscores), else every query word
  // starting one of its search words or name parts, which ranks with a name
  // matched inside a word;
  // the catalog's order breaks ties. No query: the most popular
  function rankIcons(entries, query, limit) {
    const q = String(query ?? "").trim().toLowerCase();
    if (q === "")
      return entries.slice(0, limit).map(entry => entry[0]);
    const name = q.replace(/\s+/g, "_");
    const words = q.split(/[\s_]+/).filter(word => word !== "");
    // A word starts a search word or a part of the name: a plain substring
    // test (the catalog is lowercase), run thousands of times a keystroke
    const starts = (text, word) => text.startsWith(word) || text.includes(" " + word);
    const scored = [];
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i];
      const parts = entry[0].replace(/_/g, " ");
      const tagged = words.every(word => starts(entry[1], word) || starts(parts, word));
      const s = Math.max(root.score(entry[0], name), tagged ? 50 : 0);
      if (s > 0)
        scored.push({
          name: entry[0],
          i: i,
          s: s
        });
    }
    scored.sort((a, b) => b.s - a.s || a.i - b.i);
    return scored.slice(0, limit).map(match => match.name);
  }

  // A use record's weight at `now` (ms): its count, faded with age
  function frecency(entry, now) {
    if (!entry)
      return 0;
    const days = (now - entry.last) / 86400000;
    return entry.count * (days < 1 ? 1 : days < 7 ? 0.7 : days < 30 ? 0.5 : 0.25);
  }

  // Digits and operators only, with at least one of each: worth a
  // calculator row among other results
  function looksLikeMath(text) {
    return /^[\d\s.,+\-*/^%()!×÷]+$/.test(text) && /\d/.test(text) && /[+\-*/^%!×÷]/.test(text);
  }
}
