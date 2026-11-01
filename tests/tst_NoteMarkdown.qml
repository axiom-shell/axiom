import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "NoteMarkdown"

  function kinds(doc) {
    return doc.blocks.map(block => block.kind);
  }

  function test_round_trip_data() {
    return [
      {
        tag: "empty",
        text: ""
      },
      {
        tag: "newline",
        text: "\n"
      },
      {
        tag: "plain",
        text: "# Title\n\nSome text\nmore"
      },
      {
        tag: "tasks",
        text: "- [ ] one\n- [x] two\n  * [X] nested\n1. [ ] numbered\n"
      },
      {
        tag: "empty task without space",
        text: "- [ ]\n- [ ] \n"
      },
      {
        tag: "crlf",
        text: "a\r\n- [ ] b\r\nc\r\n"
      },
      {
        tag: "mixed line endings",
        text: "a\r\nb\nc"
      },
      {
        tag: "not tasks",
        text: "-[ ] no\n- [y] no\n- [x]no\n[ ] no"
      },
      {
        tag: "blank lines between tasks",
        text: "- [ ] a\n\n\n- [ ] b"
      },
      {
        tag: "paragraphs",
        text: "\n\n# Title\n\none\ntwo\n\n\nthree\n"
      },
      {
        tag: "fence",
        text: "```js\na\n\n- [ ] not a task\n```\nafter"
      },
      {
        tag: "crlf paragraphs",
        text: "a\r\n\r\nb\r\n- [ ] c\r\n"
      }
    ];
  }

  function test_paragraphs() {
    const doc = NoteMarkdown.parse("\n# Title\n\none\ntwo\n\n\nthree\n- [ ] task\n\nend");
    compare(kinds(doc), ["text", "text", "text", "task", "text"]);
    // Blank lines stay with the paragraph above; a leading run with the first
    compare(doc.blocks[0].text, "\n# Title\n");
    compare(doc.blocks[1].text, "one\ntwo\n\n");
    compare(doc.blocks[2].text, "three");
    compare(doc.blocks[4].text, "\nend");
  }

  function test_fence_stays_one_block() {
    const doc = NoteMarkdown.parse("```\na\n\n- [ ] x\n~~~\n```\n\nafter");
    compare(kinds(doc), ["text", "text"]);
    compare(doc.blocks[0].text, "```\na\n\n- [ ] x\n~~~\n```\n");
    compare(doc.blocks[1].text, "after");
  }

  function test_trailing_line_after_tasks() {
    const doc = NoteMarkdown.parse("- [ ] a\n");
    compare(kinds(doc), ["task", "text"]);
    compare(doc.blocks[1].text, "");
    compare(kinds(NoteMarkdown.parse("a\n")), ["text"]);
  }

  function test_needs_reparse() {
    verify(!NoteMarkdown.needsReparse("one\ntwo\n\n"));
    verify(NoteMarkdown.needsReparse("one\n\ntwo"));
    verify(NoteMarkdown.needsReparse("one\n- [ ] "));
    // "- [ ]" is still being typed
    verify(!NoteMarkdown.needsReparse("one\n- [ ]"));
    verify(!NoteMarkdown.needsReparse("```\n\n- [ ] code\n"));
  }

  function test_typed_blank_line_splits_the_paragraph() {
    const doc = NoteMarkdown.setText(NoteMarkdown.parse("abc"), 0, "abc\n\nd");
    const result = NoteMarkdown.reparse(doc, {
      "block": 0,
      "pos": 6
    });
    compare(kinds(result.doc), ["text", "text"]);
    compare(result.focus, {
      "block": 1,
      "pos": 1
    });
  }

  function test_backspace_joins_paragraphs() {
    const doc = NoteMarkdown.parse("abc\n\nd");
    const result = NoteMarkdown.mergeBack(doc, 1);
    compare(NoteMarkdown.serialize(result.doc), "abc\nd");
    compare(kinds(result.doc), ["text"]);
    compare(result.focus, {
      "block": 0,
      "pos": 4
    });
  }

  function test_delete_joins_paragraphs() {
    const doc = NoteMarkdown.parse("abc\n\nd\ne");
    // At the end of the first paragraph (after its blank line)
    const result = NoteMarkdown.joinNext(doc, 0);
    compare(NoteMarkdown.serialize(result.doc), "abc\nd\ne");
    compare(kinds(result.doc), ["text"]);
  }

  function test_round_trip(data) {
    compare(NoteMarkdown.serialize(NoteMarkdown.parse(data.text)), data.text);
  }

  function test_parse_blocks() {
    const doc = NoteMarkdown.parse("intro\nmore\n- [ ] a\n- [x] b\noutro");
    compare(kinds(doc), ["text", "task", "task", "text"]);
    compare(doc.blocks[0].text, "intro\nmore");
    compare(doc.blocks[1].text, "a");
    verify(!NoteMarkdown.isChecked(doc.blocks[1]));
    verify(NoteMarkdown.isChecked(doc.blocks[2]));
    compare(NoteMarkdown.progress(doc), {
      "done": 1,
      "total": 2
    });
  }

  function test_toggle_only_touches_its_line() {
    const doc = NoteMarkdown.parse("*  keep   spacing*\n- [ ] a\n- [X] b\n");
    const once = NoteMarkdown.toggle(doc, 1).doc;
    compare(NoteMarkdown.serialize(once), "*  keep   spacing*\n- [x] a\n- [X] b\n");
    const twice = NoteMarkdown.toggle(once, 2).doc;
    compare(NoteMarkdown.serialize(twice), "*  keep   spacing*\n- [x] a\n- [ ] b\n");
    // The input is left alone
    compare(NoteMarkdown.serialize(doc), "*  keep   spacing*\n- [ ] a\n- [X] b\n");
  }

  function test_split_task() {
    const doc = NoteMarkdown.parse("  2. [x] buy milk");
    const result = NoteMarkdown.splitTask(doc, 0, 4);
    compare(NoteMarkdown.serialize(result.doc), "  2. [x] buy \n  3. [ ] milk");
    compare(result.focus, {
      "block": 1,
      "pos": 0
    });
  }

  function test_enter_on_empty_task_ends_the_list() {
    const doc = NoteMarkdown.parse("text\n- [ ] a\n- [ ] ");
    const result = NoteMarkdown.splitTask(doc, 2, 0);
    compare(NoteMarkdown.serialize(result.doc), "text\n- [ ] a\n");
    compare(kinds(result.doc), ["text", "task", "text"]);
    compare(result.focus, {
      "block": 2,
      "pos": 0
    });
  }

  function test_enter_on_empty_nested_task_outdents() {
    const doc = NoteMarkdown.parse("- [ ] a\n    - [ ] ");
    const result = NoteMarkdown.splitTask(doc, 1, 0);
    compare(NoteMarkdown.serialize(result.doc), "- [ ] a\n  - [ ] ");
  }

  function test_backspace_on_task_drops_the_box() {
    const doc = NoteMarkdown.parse("before\n- [ ] item\nafter");
    const result = NoteMarkdown.mergeBack(doc, 1);
    compare(NoteMarkdown.serialize(result.doc), "before\nitem\nafter");
    compare(kinds(result.doc), ["text"]);
    compare(result.focus, {
      "block": 0,
      "pos": 7
    });
  }

  function test_backspace_on_text_joins_the_task_above() {
    const doc = NoteMarkdown.parse("- [ ] item\nmore\nrest");
    const result = NoteMarkdown.mergeBack(doc, 1);
    compare(NoteMarkdown.serialize(result.doc), "- [ ] itemmore\nrest");
    compare(result.focus, {
      "block": 0,
      "pos": 4
    });
  }

  function test_delete_joins_the_next_block() {
    const doc = NoteMarkdown.parse("- [ ] a\n- [ ] b\nc");
    const result = NoteMarkdown.joinNext(doc, 0);
    compare(NoteMarkdown.serialize(result.doc), "- [ ] ab\nc");
    compare(result.focus, {
      "block": 0,
      "pos": 1
    });
  }

  function test_toggle_task_on_a_line() {
    const doc = NoteMarkdown.parse("one\n- two\nthree");
    const result = NoteMarkdown.toggleTask(doc, 0, 5);
    compare(NoteMarkdown.serialize(result.doc), "one\n- [ ] two\nthree");
    compare(kinds(result.doc), ["text", "task", "text"]);
    compare(result.focus, {
      "block": 1,
      "pos": 3
    });
    // And back
    const back = NoteMarkdown.toggleTask(result.doc, 1, 0);
    compare(NoteMarkdown.serialize(back.doc), "one\ntwo\nthree");
    compare(kinds(back.doc), ["text"]);
  }

  function test_toggle_task_without_focus_appends() {
    const empty = NoteMarkdown.toggleTask(NoteMarkdown.parse(""), -1, 0);
    compare(NoteMarkdown.serialize(empty.doc), "- [ ] ");
    compare(empty.focus, {
      "block": 0,
      "pos": 0
    });
    const after = NoteMarkdown.toggleTask(NoteMarkdown.parse("- [ ] a"), -1, 0);
    compare(NoteMarkdown.serialize(after.doc), "- [ ] a\n- [ ] ");
  }

  function test_toggle_bullet() {
    const doc = NoteMarkdown.parse("a\n  b");
    const on = NoteMarkdown.toggleBullet(doc, 0, 3);
    compare(NoteMarkdown.serialize(on.doc), "a\n  - b");
    const off = NoteMarkdown.toggleBullet(on.doc, 0, 3);
    compare(NoteMarkdown.serialize(off.doc), "a\n  b");
  }

  function test_set_text_keeps_a_task_on_one_line() {
    const doc = NoteMarkdown.setText(NoteMarkdown.parse("- [ ] a"), 0, "pasted\ntext");
    compare(NoteMarkdown.serialize(doc), "- [ ] pasted text");
  }

  function test_continue_prefix() {
    compare(NoteMarkdown.continuePrefix("- item"), {
      "prefix": "- "
    });
    compare(NoteMarkdown.continuePrefix("  9) item"), {
      "prefix": "  10) "
    });
    compare(NoteMarkdown.continuePrefix("- "), {
      "clear": true
    });
    compare(NoteMarkdown.continuePrefix("plain"), null);
  }

  function test_typed_task_is_reparsed_keeping_the_cursor() {
    const doc = NoteMarkdown.parse("intro");
    const typed = NoteMarkdown.setText(doc, 0, "intro\n- [ ] milk");
    verify(NoteMarkdown.hasTaskLine(typed.blocks[0].text));
    verify(!NoteMarkdown.hasTaskLine("intro\n- [ ]"));
    const result = NoteMarkdown.reparse(typed, {
      "block": 0,
      "pos": 16
    });
    compare(kinds(result.doc), ["text", "task"]);
    compare(result.focus, {
      "block": 1,
      "pos": 4
    });
    compare(NoteMarkdown.serialize(result.doc), "intro\n- [ ] milk");
  }

  function test_line_of_and_position_at() {
    const doc = NoteMarkdown.parse("a\nbc\n- [ ] task\nd");
    compare(NoteMarkdown.lineOf(doc, 0, 3), {
      "line": 1,
      "col": 1
    });
    compare(NoteMarkdown.lineOf(doc, 1, 2), {
      "line": 2,
      "col": 8
    });
    compare(NoteMarkdown.positionAt(doc, 1, 1), {
      "block": 0,
      "pos": 3
    });
    compare(NoteMarkdown.positionAt(doc, 2, 3), {
      "block": 1,
      "pos": 0
    });
    compare(NoteMarkdown.positionAt(doc, 3, 9), {
      "block": 2,
      "pos": 1
    });
  }

  function test_indent_task() {
    const doc = NoteMarkdown.parse("- [ ] a");
    const indented = NoteMarkdown.indentTask(doc, 0, 1).doc;
    compare(NoteMarkdown.serialize(indented), "  - [ ] a");
    compare(NoteMarkdown.serialize(NoteMarkdown.indentTask(indented, 0, -1).doc), "- [ ] a");
  }
}
