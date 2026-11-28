import QtQuick
import QtTest
import qs.components.methods

// SectionFolds: the layouts editor's list sections are open unless chosen
// otherwise (Tools closed), and what was chosen survives a save and a load.
TestCase {
  name: "SectionFolds"

  function test_defaults() {
    verify(SectionFolds.isOpen({}, "pages"), "pages start open");
    verify(SectionFolds.isOpen({}, "menus"), "menus start open");
    verify(SectionFolds.isOpen({}, "screens"), "screens start open");
    verify(!SectionFolds.isOpen({}, "tools"), "tools start closed");
    verify(!SectionFolds.isOpen(null, "tools"), "no state at all: the defaults");
  }

  function test_a_choice_wins_over_the_default() {
    let folds = SectionFolds.withOpen({}, "tools", true);
    verify(SectionFolds.isOpen(folds, "tools"));
    folds = SectionFolds.withOpen(folds, "menus", false);
    verify(!SectionFolds.isOpen(folds, "menus"));
    verify(SectionFolds.isOpen(folds, "pages"), "the others keep their default");
  }

  function test_toggling_keeps_the_argument() {
    const before = {
      "menus": false
    };
    SectionFolds.withOpen(before, "tools", true);
    compare(before, {
      "menus": false
    });
  }

  function test_choices_read_back_after_a_save_and_load() {
    let folds = SectionFolds.withOpen({}, "tools", true);
    folds = SectionFolds.withOpen(folds, "pages", false);
    const loaded = SectionFolds.clean(JSON.parse(JSON.stringify(folds)));
    verify(SectionFolds.isOpen(loaded, "tools"), "tools stays open");
    verify(!SectionFolds.isOpen(loaded, "pages"), "pages stays closed");
    verify(SectionFolds.isOpen(loaded, "menus"), "untouched: open");
  }

  function test_clean_drops_what_is_not_a_choice() {
    compare(SectionFolds.clean(null), {});
    compare(SectionFolds.clean([true]), {});
    compare(SectionFolds.clean("x"), {});
    compare(SectionFolds.clean({
      "tools": "yes",
      "menus": false,
      "pages": 1
    }), {
      "menus": false
    });
  }

  function test_from_saved_reads_the_old_shapes() {
    compare(SectionFolds.fromSaved({
      "keybindsFolded": ["a", 3]
    }), {
      "bind:a": false
    });
    compare(SectionFolds.fromSaved({
      "sectionFolds": {
        "bind:a": true
      },
      "keybindsFolded": ["a", "b"]
    }), {
      "bind:a": true,
      "bind:b": false
    });
    compare(SectionFolds.fromSaved({
      "layoutsFolds": {
        "tools": true
      }
    }), {
      "tools": true
    });
    compare(SectionFolds.fromSaved(null), {});
  }
}
