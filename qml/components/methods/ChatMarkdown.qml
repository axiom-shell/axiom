pragma Singleton
import QtQuick

/**
 * Splits a chat reply into what the chat draws separately: Markdown prose
 * (a TextEdit in MarkdownText) and fenced code blocks (a box of their own,
 * with a copy button). Pure; safe to call on a reply still streaming in,
 * where the last fence may not be closed yet.
 */
QtObject {
  id: root

  /**
   * @return [{ kind: "md" | "code", text, lang, open }], `open` on a code
   *         block whose closing fence hasn't arrived
   */
  function segments(text) {
    const out = [];
    const lines = String(text ?? "").split("\n");
    let prose = [];
    let code = null;

    const flushProse = () => {
      const joined = prose.join("\n");
      if (joined.trim() !== "")
        out.push({
          kind: "md",
          text: joined.replace(/^\n+|\n+$/g, ""),
          lang: "",
          open: false
        });
      prose = [];
    };

    for (const line of lines) {
      if (code) {
        const close = line.match(/^ {0,3}(`{3,}|~{3,})\s*$/);
        // Models often wrap a whole Markdown answer in a ```markdown fence
        // with fenced code inside it; Markdown fences don't nest, so count
        // the inner ones there
        if (code.nests && !close && /^ {0,3}(`{3,}|~{3,})\S/.test(line)) {
          code.depth += 1;
          code.lines.push(line);
          continue;
        }
        if (close && code.depth > 0) {
          code.depth -= 1;
          code.lines.push(line);
          continue;
        }
        if (close && close[1][0] === code.fence[0] && close[1].length >= code.fence.length) {
          out.push({
            kind: "code",
            text: code.lines.join("\n"),
            lang: code.lang,
            open: false
          });
          code = null;
        } else {
          code.lines.push(line);
        }
        continue;
      }
      const open = line.match(/^ {0,3}(`{3,}|~{3,})\s*([^`\s]*)/);
      if (open) {
        flushProse();
        code = {
          fence: open[1],
          lang: open[2] ?? "",
          lines: [],
          nests: /^(markdown|md)$/i.test(open[2] ?? ""),
          depth: 0
        };
        continue;
      }
      prose.push(line);
    }
    // An unclosed fence with nothing in it yet draws nothing
    if (code && code.lines.join("").trim() !== "")
      out.push({
        kind: "code",
        text: code.lines.join("\n"),
        lang: code.lang,
        open: true
      });
    else if (!code)
      flushProse();
    return out;
  }
}
