import QtQuick
import QtTest
import qs.config
import qs.components.reusable
import qs.components.forms

// The text entries (the layout harness): hidden text keeps every input
// method out (the hints follow the echo mode), a CommitEntry keeps what was
// typed over a value pushed in until it commits, and a live one emits on each
// edit.
TestCase {
  id: root

  name: "Entries"
  when: windowShown
  visible: true
  width: 600
  height: 400

  Harness {
    id: harness
  }

  readonly property int hidden: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhHiddenText

  Component {
    id: entryComp

    StyledTextEntry {
      width: 300
    }
  }

  Component {
    id: commitComp

    CommitEntry {
      property var commits: []
      property var edits: []
      width: 300
      onCommitted: text => commits.push(text)
      onEdited: text => edits.push(text)
    }
  }

  Component {
    id: submitComp

    SubmitEntry {
      width: 300
      buttonIcon: "link"
    }
  }

  // Types into the entry as the user does: the text, then the signal the
  // field emits for an edit
  function type(entry, text) {
    entry.input.forceActiveFocus();
    entry.input.text = text;
    entry.input.textEdited();
  }

  function init() {
    harness.configure({
      "scale": 100,
      "fontSize": 11
    });
  }

  function test_plain_entry_has_no_hints() {
    const entry = createTemporaryObject(entryComp, root);
    compare(entry.input.inputMethodHints & root.hidden, 0);
  }

  function test_hidden_entry_keeps_input_methods_out() {
    const entry = createTemporaryObject(entryComp, root);
    entry.input.echoMode = TextInput.Password;
    compare(entry.input.inputMethodHints & root.hidden, root.hidden);
    compare(entry.input.passwordMaskDelay, 0);
    entry.input.echoMode = TextInput.Normal;
    compare(entry.input.inputMethodHints & root.hidden, 0);
  }

  function test_secret_submit_entry_hides_its_text() {
    const entry = createTemporaryObject(submitComp, root, {
      "secret": true
    });
    compare(entry.input.echoMode, TextInput.Password);
    compare(entry.input.inputMethodHints & root.hidden, root.hidden);
    entry.secret = false;
    compare(entry.input.echoMode, TextInput.Normal);
  }

  function test_revealed_password_keeps_the_hints() {
    const entry = createTemporaryObject(passwordComp, root, {
      "reveal": true
    });
    compare(entry.input.echoMode, TextInput.Normal);
    compare(entry.input.inputMethodHints & root.hidden, root.hidden);
  }

  // An answer that is never hidden (a user name) is no secret: the input
  // method isn't shut out of it
  function test_non_secret_password_entry_takes_input_methods() {
    const entry = createTemporaryObject(passwordComp, root, {
      "reveal": true,
      "secret": false
    });
    compare(entry.input.inputMethodHints & root.hidden, 0);
    const secret = createTemporaryObject(passwordComp, root);
    compare(secret.input.inputMethodHints & root.hidden, root.hidden);
  }

  function test_submit_entry_does_not_submit_when_it_cannot() {
    const entry = createTemporaryObject(submitComp, root);
    const spy = createTemporaryObject(spyComp, root, {
      "target": entry,
      "signalName": "submitted"
    });
    entry.input.forceActiveFocus();
    keyClick(Qt.Key_Return);
    compare(spy.count, 0);
  }

  function test_submit_entry_submits_on_enter() {
    const entry = createTemporaryObject(submitComp, root, {
      "text": "x"
    });
    const spy = createTemporaryObject(spyComp, root, {
      "target": entry,
      "signalName": "submitted"
    });
    entry.input.forceActiveFocus();
    keyClick(Qt.Key_Return);
    compare(spy.count, 1);
  }

  Component {
    id: passwordComp

    PasswordEntry {
      width: 300
    }
  }

  Component {
    id: spyComp

    SignalSpy {}
  }

  function test_commit_entry_shows_value_and_follows_it() {
    const entry = createTemporaryObject(commitComp, root, {
      "value": "one"
    });
    compare(entry.text, "one");
    entry.value = "two";
    compare(entry.text, "two");
  }

  function test_commit_entry_keeps_typed_text_until_commit() {
    const entry = createTemporaryObject(commitComp, root, {
      "value": "one"
    });
    root.type(entry, "typed");
    entry.value = "pushed";
    compare(entry.text, "typed");
    compare(entry.commits.length, 0);
    entry.commitTyped();
    compare(entry.commits, ["typed"]);
    compare(entry.edits.length, 0);
    // Nothing held: a second commit says nothing
    entry.commitTyped();
    compare(entry.commits.length, 1);
  }

  function test_commit_entry_discard_goes_back_to_value() {
    const entry = createTemporaryObject(commitComp, root, {
      "value": "one"
    });
    root.type(entry, "typed");
    entry.discardTyped();
    compare(entry.text, "one");
    entry.commitTyped();
    compare(entry.commits.length, 0);
  }

  function test_commit_entry_commits_on_losing_focus() {
    const entry = createTemporaryObject(commitComp, root, {
      "value": "one"
    });
    root.type(entry, "typed");
    entry.input.focus = false;
    compare(entry.commits, ["typed"]);
  }

  function test_commit_on_destroy_is_optional() {
    const kept = createTemporaryObject(commitComp, root, {
      "value": "one"
    });
    const spy = createTemporaryObject(spyComp, root, {
      "target": kept,
      "signalName": "committed"
    });
    root.type(kept, "typed");
    kept.commitOnDestroy = false;
    kept.destroy();
    wait(0);
    compare(spy.count, 0);
  }

  function test_live_entry_emits_each_edit() {
    const entry = createTemporaryObject(commitComp, root, {
      "value": "one",
      "live": true
    });
    root.type(entry, "a");
    root.type(entry, "ab");
    compare(entry.edits, ["a", "ab"]);
    compare(entry.commits.length, 0);
  }

  Component {
    id: escapeComp

    Item {
      property alias entry: sub
      property int parentEscapes: 0
      property int cancels: 0
      width: 300
      height: 40
      Keys.onEscapePressed: parentEscapes++

      SubmitEntry {
        id: sub
        width: 300
        buttonIcon: "link"
        onCancelled: parent.cancels++
      }
    }
  }

  // Escape goes on to the parents unless the entry is told to cancel
  function test_submitEntry_escape() {
    const host = createTemporaryObject(escapeComp, root);
    host.entry.input.forceActiveFocus();
    keyClick(Qt.Key_Escape);
    compare(host.parentEscapes, 1, "Escape passes on");
    compare(host.cancels, 0);
    host.entry.escapeCancels = true;
    keyClick(Qt.Key_Escape);
    compare(host.cancels, 1);
    compare(host.parentEscapes, 1, "and stops here");
  }

  Component {
    id: pushedComp

    CommitEntry {
      width: 300
      value: ""
      onCommitted: text => value = text
    }
  }

  // Tab out commits what was typed and the pushed value is that text, at once and after
  function test_commitEntry_keeps_typed_text_on_tab_out() {
    const entry = createTemporaryObject(pushedComp, root);
    root.type(entry, "typed");
    entry.input.focus = false;
    compare(entry.text, "typed");
    wait(0);
    compare(entry.text, "typed");
  }
}
