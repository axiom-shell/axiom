pragma Singleton
import QtQuick

/**
 * A note's Markdown as blocks for the notes editor (content/parts/notes/
 * NoteEditor): paragraphs of plain lines (split at blank lines, which stay
 * with the paragraph above; a code fence is never split, and holds no
 * tasks), and task lines (`- [ ] text`), each its own row with a checkbox.
 * Every structural edit parses the note again, so its blocks are always what
 * parse() would give. Lossless: serialize(parse(text)) is text, and an
 * edit only rewrites the lines it touches, so a note in a linked folder
 * (Obsidian, a synced vault) keeps its formatting.
 *
 * A doc is { blocks, eol, trailingNewline }. A block is
 *   { kind: "text", text }  one or more lines, joined with "\n"
 *   { kind: "task", indent, marker, mark, sep, text }  one line:
 *     indent + marker + " [" + mark + "]" + sep + text
 *
 * Edits take a doc and return { doc, focus }, a new doc and where the
 * cursor goes ({ block, pos }, or null). They never modify their input.
 */
QtObject {
  id: root

  // indent, list marker (- * + or 1. 1)), the box's mark, the space after it
  readonly property var _taskPattern: /^(\s*)([-*+]|\d+[.)]) \[([ xX])\]( |$)(.*)$/
  readonly property var _bulletPattern: /^(\s*)([-*+]|\d+[.)]) /
  readonly property var _fencePattern: /^\s{0,3}(`{3,}|~{3,})/

  // A text block whose next non-blank line starts a new paragraph: it has
  // text, and a blank line after it (blank lines stay with the paragraph
  // above them)
  function _paragraphEnded(text) {
    const lines = text.split("\n");
    return lines[lines.length - 1].trim() === "" && lines.some(line => line.trim() !== "");
  }

  function parse(text) {
    const source = String(text ?? "");
    // CRLF only when every line break is one: a mixed file splits on "\n",
    // its stray "\r"s staying in the text, so it still round-trips
    const breaks = (source.match(/\n/g) ?? []).length;
    const eol = breaks > 0 && (source.match(/\r\n/g) ?? []).length === breaks ? "\r\n" : "\n";
    const lines = source.split(eol);
    // The file's final line break, unless a task ends the note: then the
    // empty line after it is a block, somewhere to put the cursor
    const trailingNewline = lines.length > 1 && lines[lines.length - 1] === "" && !root._taskPattern.test(lines[lines.length - 2]);
    if (trailingNewline)
      lines.pop();
    const blocks = [];
    // The open code fence's marker ("```", "~~~~"), or ""
    let fence = "";
    lines.forEach(line => {
      const inFence = fence !== "";
      const marker = root._fencePattern.exec(line);
      if (marker && !inFence)
        fence = marker[1];
      else if (marker && marker[1][0] === fence[0] && marker[1].length >= fence.length && line.trim() === marker[1])
        fence = "";
      const task = inFence ? null : root.taskFromLine(line);
      if (task) {
        blocks.push(task);
        return;
      }
      const last = blocks[blocks.length - 1];
      if (last && last.kind === "text" && (inFence || !root._paragraphEnded(last.text) || line.trim() === ""))
        last.text += "\n" + line;
      else
        blocks.push({
          "kind": "text",
          "text": line
        });
    });
    return {
      "blocks": blocks,
      "eol": eol,
      "trailingNewline": trailingNewline
    };
  }

  function serialize(doc) {
    const lines = [].concat(...doc.blocks.map(block => block.kind === "task" ? [root.taskLine(block)] : block.text.split("\n")));
    return lines.join(doc.eol) + (doc.trailingNewline ? doc.eol : "");
  }

  // A task block from one line, or null when the line isn't a task
  function taskFromLine(line) {
    const match = root._taskPattern.exec(line);
    if (!match)
      return null;
    return {
      "kind": "task",
      "indent": match[1],
      "marker": match[2],
      "mark": match[3],
      "sep": match[4],
      "text": match[5]
    };
  }

  function taskLine(block) {
    // "- [ ]" alone keeps having no space; any text gets one
    const sep = block.text === "" ? block.sep : " ";
    return block.indent + block.marker + " [" + block.mark + "]" + sep + block.text;
  }

  function isChecked(block) {
    return block.kind === "task" && block.mark !== " ";
  }

  function newTask(indent, marker, text) {
    return {
      "kind": "task",
      "indent": indent ?? "",
      "marker": marker ?? "-",
      "mark": " ",
      "sep": " ",
      "text": text ?? ""
    };
  }

  // Counts (checked, total) for a summary
  function progress(doc) {
    const tasks = doc.blocks.filter(block => block.kind === "task");
    return {
      "done": tasks.filter(block => root.isChecked(block)).length,
      "total": tasks.length
    };
  }

  // The marker for the item after one with `marker` (1. → 2.)
  function nextMarker(marker) {
    const number = /^(\d+)([.)])$/.exec(marker);
    return number ? (parseInt(number[1]) + 1) + number[2] : marker;
  }

  // Enter at the end of a plain list line: { prefix } to start the next
  // line with, { clear: true } when the line is an empty item (Enter ends
  // the list), or null when the line isn't a list item
  function continuePrefix(line) {
    const match = root._bulletPattern.exec(line);
    if (!match)
      return null;
    if (line.slice(match[0].length).trim() === "")
      return {
        "clear": true
      };
    return {
      "prefix": match[1] + root.nextMarker(match[2]) + " "
    };
  }

  // A line that became a task as it was typed ("- [ ] " with its space),
  // so the editor re-parses its block
  function hasTaskLine(text) {
    return /^\s*([-*+]|\d+[.)]) \[[ xX]\] /m.test(text);
  }

  // A text block's typed text no longer parses as one paragraph (a task
  // line, or a blank line followed by more text), so the editor re-parses
  function needsReparse(text) {
    const blocks = root.parse(text).blocks;
    if (blocks.length === 1 && blocks[0].kind === "text")
      return false;
    // "- [ ]" still being typed waits for its space
    return !blocks.some(block => block.kind === "task" && block.sep === "" && block.text === "") || root.hasTaskLine(text);
  }

  // Where (block, pos) is in the note's lines: { line, col }, col counting
  // a task's "- [ ] " prefix
  function lineOf(doc, index, pos) {
    let line = 0;
    for (let i = 0; i < index; ++i)
      line += doc.blocks[i].kind === "task" ? 1 : doc.blocks[i].text.split("\n").length;
    const block = doc.blocks[index];
    if (!block)
      return {
        "line": line,
        "col": 0
      };
    if (block.kind === "task")
      return {
        "line": line,
        "col": root.taskLine(block).length - block.text.length + pos
      };
    const before = block.text.slice(0, pos);
    return {
      "line": line + before.split("\n").length - 1,
      "col": pos - (before.lastIndexOf("\n") + 1)
    };
  }

  // The reverse of lineOf: { block, pos } for a line and column (a column
  // inside a task's prefix lands at its text's start)
  function positionAt(doc, line, col) {
    let first = 0;
    for (let i = 0; i < doc.blocks.length; ++i) {
      const block = doc.blocks[i];
      if (block.kind === "task") {
        if (line === first)
          return {
            "block": i,
            "pos": Math.min(block.text.length, Math.max(0, col - (root.taskLine(block).length - block.text.length)))
          };
        first += 1;
        continue;
      }
      const lines = block.text.split("\n");
      if (line < first + lines.length) {
        let pos = 0;
        for (let l = 0; l < line - first; ++l)
          pos += lines[l].length + 1;
        return {
          "block": i,
          "pos": pos + Math.min(col, lines[line - first].length)
        };
      }
      first += lines.length;
    }
    const last = doc.blocks.length - 1;
    return {
      "block": last,
      "pos": doc.blocks[last]?.text.length ?? 0
    };
  }

  // Tab / Shift+Tab on a task: two spaces more or less
  function indentTask(doc, index, delta) {
    const copy = root._copy(doc);
    const block = copy.blocks[index];
    if (block?.kind === "task") {
      if (delta > 0)
        block.indent = (block.indent.startsWith("\t") ? "\t" : "  ") + block.indent;
      else
        block.indent = block.indent.startsWith("\t") ? block.indent.slice(1) : block.indent.slice(Math.min(2, block.indent.length));
    }
    return {
      "doc": copy,
      "focus": null
    };
  }

  // --- Edits ---

  function _copy(doc) {
    return {
      "blocks": doc.blocks.map(block => Object.assign({}, block)),
      "eol": doc.eol,
      "trailingNewline": doc.trailingNewline
    };
  }

  // Parses the edited note again (after an edit, or a task typed or pasted
  // into a text block), so its text is split into paragraphs as parse()
  // would, moving `focus` ({ block, pos }) along by line and column
  function reparse(doc, focus) {
    const at = focus && doc.blocks.length > 0 ? root.lineOf(doc, focus.block, focus.pos) : null;
    const parsed = root.parse(root.serialize(doc));
    return {
      "doc": parsed,
      "focus": at ? root.positionAt(parsed, at.line, at.col) : focus ? {
        "block": 0,
        "pos": 0
      } : null
    };
  }

  // Line index and bounds of the line holding `pos` in a text block
  function _lineAt(text, pos) {
    const start = text.lastIndexOf("\n", pos - 1) + 1;
    const newline = text.indexOf("\n", pos);
    const end = newline < 0 ? text.length : newline;
    return {
      "start": start,
      "end": end,
      "line": text.slice(start, end)
    };
  }

  // Splits text block `index` around the line holding `pos`, putting
  // `blocks` in its place: returns the new list's index of the first one
  function _replaceLine(doc, index, pos, replacement) {
    const text = doc.blocks[index].text;
    const at = root._lineAt(text, pos);
    const parts = [];
    if (at.start > 0)
      parts.push({
        "kind": "text",
        "text": text.slice(0, at.start - 1)
      });
    const first = index + parts.length;
    replacement.forEach(block => parts.push(block));
    if (at.end < text.length)
      parts.push({
        "kind": "text",
        "text": text.slice(at.end + 1)
      });
    doc.blocks.splice(index, 1, ...parts);
    return first;
  }

  function toggle(doc, index) {
    const copy = root._copy(doc);
    const block = copy.blocks[index];
    if (block?.kind === "task")
      block.mark = block.mark === " " ? "x" : " ";
    return {
      "doc": copy,
      "focus": null
    };
  }

  // Sets a block's text (typing); a task keeps to one line
  function setText(doc, index, text) {
    const copy = root._copy(doc);
    const block = copy.blocks[index];
    if (block)
      block.text = block.kind === "task" ? String(text).replace(/\r?\n/g, " ") : String(text);
    return copy;
  }

  // Enter in task `index` at `pos`: a new task with the text after the
  // cursor. On an empty task it outdents, or at the top level ends the list
  function splitTask(doc, index, pos) {
    const copy = root._copy(doc);
    const block = copy.blocks[index];
    if (block.text.trim() === "") {
      if (block.indent !== "") {
        block.indent = block.indent.startsWith("\t") ? block.indent.slice(1) : block.indent.slice(Math.min(2, block.indent.length));
        return {
          "doc": copy,
          "focus": {
            "block": index,
            "pos": 0
          }
        };
      }
      copy.blocks[index] = {
        "kind": "text",
        "text": ""
      };
      return root.reparse(copy, {
        "block": index,
        "pos": 0
      });
    }
    const after = block.text.slice(pos);
    block.text = block.text.slice(0, pos);
    copy.blocks.splice(index + 1, 0, root.newTask(block.indent, root.nextMarker(block.marker), after));
    return {
      "doc": copy,
      "focus": {
        "block": index + 1,
        "pos": 0
      }
    };
  }

  // Backspace at the start of block `index`: a task loses its checkbox and
  // becomes a plain line; a text block's first line joins the task above
  function mergeBack(doc, index) {
    const copy = root._copy(doc);
    const block = copy.blocks[index];
    if (!block)
      return {
        "doc": copy,
        "focus": null
      };
    if (block.kind === "task") {
      copy.blocks[index] = {
        "kind": "text",
        "text": block.text
      };
      return root.reparse(copy, {
        "block": index,
        "pos": 0
      });
    }
    const previous = copy.blocks[index - 1];
    if (!previous)
      return {
        "doc": copy,
        "focus": {
          "block": index,
          "pos": 0
        }
      };
    const newline = block.text.indexOf("\n");
    const first = newline < 0 ? block.text : block.text.slice(0, newline);
    const pos = previous.text.length;
    previous.text += first;
    if (newline < 0)
      copy.blocks.splice(index, 1);
    else
      block.text = block.text.slice(newline + 1);
    return root.reparse(copy, {
      "block": index - 1,
      "pos": pos
    });
  }

  // Delete at the end of block `index`: the next task's text, or the next
  // text block's first line, joins this block's last line
  function joinNext(doc, index) {
    const copy = root._copy(doc);
    const block = copy.blocks[index];
    const next = copy.blocks[index + 1];
    if (!block || !next)
      return {
        "doc": copy,
        "focus": null
      };
    const pos = block.text.length;
    if (next.kind === "task") {
      block.text += next.text;
      copy.blocks.splice(index + 1, 1);
    } else {
      const newline = next.text.indexOf("\n");
      block.text += newline < 0 ? next.text : next.text.slice(0, newline);
      if (newline < 0)
        copy.blocks.splice(index + 1, 1);
      else
        next.text = next.text.slice(newline + 1);
    }
    return root.reparse(copy, {
      "block": index,
      "pos": pos
    });
  }

  // The checklist button. In a text block the line holding `pos` becomes a
  // task (a bullet's marker is dropped); a task turns back into a line;
  // with nothing focused (index < 0) a task is added at the end
  function toggleTask(doc, index, pos) {
    const copy = root._copy(doc);
    const block = copy.blocks[index];
    if (!block) {
      const last = copy.blocks[copy.blocks.length - 1];
      // An empty last line becomes the task instead of leaving a gap
      if (last && last.kind === "text" && root._lineAt(last.text, last.text.length).line === "") {
        const first = root._replaceLine(copy, copy.blocks.length - 1, last.text.length, [root.newTask()]);
        return root.reparse(copy, {
          "block": first,
          "pos": 0
        });
      }
      copy.blocks.push(root.newTask());
      return root.reparse(copy, {
        "block": copy.blocks.length - 1,
        "pos": 0
      });
    }
    if (block.kind === "task") {
      copy.blocks[index] = {
        "kind": "text",
        "text": block.indent + block.text
      };
      return root.reparse(copy, {
        "block": index,
        "pos": copy.blocks[index].text.length
      });
    }
    const line = root._lineAt(block.text, pos).line;
    const bullet = root._bulletPattern.exec(line);
    const indent = /^\s*/.exec(line)[0];
    const text = bullet ? line.slice(bullet[0].length) : line.slice(indent.length);
    const task = root.newTask(indent, bullet ? bullet[2] : "-", text);
    const first = root._replaceLine(copy, index, pos, [task]);
    return root.reparse(copy, {
      "block": first,
      "pos": text.length
    });
  }

  // The bullet button: a plain line gains or loses "- ", a task becomes a
  // bulleted line
  function toggleBullet(doc, index, pos) {
    const copy = root._copy(doc);
    const block = copy.blocks[index];
    if (!block) {
      copy.blocks.push({
        "kind": "text",
        "text": "- "
      });
      return root.reparse(copy, {
        "block": copy.blocks.length - 1,
        "pos": 2
      });
    }
    if (block.kind === "task") {
      copy.blocks[index] = {
        "kind": "text",
        "text": block.indent + block.marker + " " + block.text
      };
      return root.reparse(copy, {
        "block": index,
        "pos": copy.blocks[index].text.length
      });
    }
    const at = root._lineAt(block.text, pos);
    const bullet = root._bulletPattern.exec(at.line);
    const indent = /^\s*/.exec(at.line)[0];
    const line = bullet ? indent + at.line.slice(bullet[0].length) : indent + "- " + at.line.slice(indent.length);
    block.text = block.text.slice(0, at.start) + line + block.text.slice(at.end);
    return root.reparse(copy, {
      "block": index,
      "pos": at.start + line.length
    });
  }
}
